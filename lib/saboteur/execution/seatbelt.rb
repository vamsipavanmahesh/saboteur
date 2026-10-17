# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fiddle"

module Saboteur
  module Execution
    # The macOS counterpart of Sandbox (Landlock): a Seatbelt profile
    # applied with sandbox_init inside the mutant child. sandbox-exec and
    # sandbox_init are deprecated by Apple with no published replacement
    # and no removal timeline (#436 tracks how Apple, Chrome, Codex,
    # Claude Code, Bazel and Nix respond), so Seatbelt is opt-in and the
    # probe below fails closed: a child that cannot be confined runs with
    # the hazard guard and canary only, never silently "sandboxed".
    #
    # Like Sandbox, requiring this file is inert off macOS: libsandbox is
    # dlopened lazily by the first probe, and the probe forks so the
    # irreversible sandbox_init never touches the run's own process.
    module Seatbelt
      LIBSANDBOX = "/usr/lib/system/libsystem_sandbox.dylib"
      LIBSYSTEM = "/usr/lib/libSystem.B.dylib"
      F_GETPATH = 50
      PATH_MAX = 1024

      # The probe profile must deny the write it then attempts.
      PROBE_PROFILE = "(version 1)(deny default)"

      # sandbox_init error texts that say the facility is genuinely gone
      # (a future macOS without Seatbelt): degrade, noted once. Anything
      # else (a profile syntax tightening, EPERM, a lost child) fails
      # closed the same way: no hook, children run with the guard and
      # canary, noted once - never silently unsandboxed.
      UNSUPPORTED_ERRORS = ["operation not supported", "function not implemented"].freeze

      module_function

      def darwin?
        RUBY_PLATFORM.include?("darwin")
      end

      # One forked behavioral probe, memoized per process:
      # :unsupported_platform off macOS, :ok when a deny-default profile
      # really blocks a write, :unavailable when sandbox_init reports the
      # facility missing, :unenforced when the API claims success but the
      # write goes through, :error for anything else. Behavioral, not
      # symbol presence: a macOS update that rejects the profile language
      # shows up here, not in a dlopen.
      def probe
        return @probe if defined?(@probe)
        return @probe = :unsupported_platform unless darwin?

        @probe = run_probe
      rescue Fiddle::DLError
        @probe = :unavailable
      end

      def available?
        probe == :ok
      end

      # Called at the top of a mutant child, mirroring Sandbox.restrict!:
      # irreversible and fail-closed - a child whose profile does not apply
      # must not run the mutant. keep_fds is Sandbox's hook contract
      # (#234): Landlock gates opens, so its children keep writing through
      # descriptors the parent opened (their logs); Seatbelt checks
      # file-write* on EVERY write, so those inherited files join the
      # profile as literal grants instead. Pipes and sockets among them
      # have no path and need no grant.
      def restrict!(writable:, keep_fds: [])
        profile = Profile.build(writable: writable, inherited_files: fd_paths(keep_fds))
        rc, message = sandbox_init(profile)
        unless rc.zero?
          raise Error, "the Seatbelt sandbox refused to engage (#{message}); the mutant does not run unconfined"
        end

        nil
      end

      # fcntl(F_GETPATH) maps an inherited descriptor back to its path; a
      # descriptor without one (pipe, socket) is skipped.
      def fd_paths(keep_fds)
        keep_fds.filter_map do |fd|
          buffer = Fiddle::Pointer.malloc(PATH_MAX)
          LibSystem.fcntl_fn.call(fd, F_GETPATH, buffer).negative? ? nil : buffer.to_s
        end
      end

      def classify(verdict)
        case verdict
        when "ok" then :ok
        when "unenforced" then :unenforced
        when /\Ainit_failed:(?<message>.*)\z/m
          message = Regexp.last_match[:message].downcase
          UNSUPPORTED_ERRORS.any? { |text| message.include?(text) } ? :unavailable : :error
        else
          :error
        end
      end

      def run_probe
        reader, writer = IO.pipe
        pid = fork { probe_child(writer) }
        writer.close
        verdict = reader.read
        reader.close
        Process.waitpid(pid)
        classify(verdict)
      ensure
        reader.close unless reader.closed?
        writer.close unless writer.closed?
      end

      # Child only: confine, then attempt the write the profile must block.
      # The parent reads a single verdict word; exit! so no at_exit hook or
      # finalizer runs under the sandbox.
      def probe_child(writer)
        rc, message = sandbox_init(PROBE_PROFILE)
        verdict =
          if rc.zero?
            begin
              File.open(File::NULL, "w") { true }
              "unenforced"
            rescue SystemCallError, IOError
              "ok"
            end
          else
            "init_failed:#{message}"
          end
        writer.write(verdict)
        writer.close
        exit!(0)
      end

      # int sandbox_init(const char *profile, uint64_t flags, char **errorbuf)
      def sandbox_init(profile)
        errbuf = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP)
        rc = LibSandbox.sandbox_init_fn.call(profile, 0, errbuf)
        return [0, nil] if rc.zero?

        # errorbuf is a char**: dereference once to reach the message.
        message = begin
          address = errbuf[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
          address&.positive? ? Fiddle::Pointer.new(address).to_s : "unknown"
        rescue StandardError
          "unknown"
        end
        [rc, "sandbox_init: #{message}"]
      end

      # fcntl for the F_GETPATH lookup; lazy like LibSandbox.
      module LibSystem
        module_function

        def fcntl_fn
          @fcntl_fn ||= Fiddle::Function.new(
            Fiddle.dlopen(Seatbelt::LIBSYSTEM)["fcntl"],
            [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
        end
      end

      # Lazy, so requiring the file on Linux or a stripped macOS stays inert
      # (mirrors Sandbox::LibC, #178).
      module LibSandbox
        module_function

        def handle
          @handle ||= Fiddle.dlopen(Seatbelt::LIBSANDBOX)
        end

        def sandbox_init_fn
          @sandbox_init_fn ||= Fiddle::Function.new(
            handle["sandbox_init"],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )
        end
      end

      # A Landlock-shaped Seatbelt profile: reads, execution, network and
      # IPC stay allowed everywhere (allow default); only writes are
      # denied, then re-allowed under the granted dirs and /dev/null -
      # exactly the Sandbox grant semantics. allow-default is deliberate:
      # deny-default profiles break on macOS updates whenever Apple adds a
      # mach service the profile did not name, the failure mode behind the
      # macOS 26 sandbox breakage reports (#436).
      module Profile
        HEADER = "(version 1)\n"

        module_function

        # inherited_files: already-open logs the child must keep writing
        # (#234) - granted per file, never the cache dir that holds them.
        def build(writable:, inherited_files: [])
          lines = [HEADER, "(allow default)\n", "(deny file-write*)\n"]
          writable.each do |dir|
            lines << %((allow file-write* (subpath "#{escape(dir)}"))\n)
          end
          (inherited_files + [File::NULL]).uniq.each do |file|
            lines << %((allow file-write* (literal "#{escape(file)}"))\n)
          end
          lines.join
        end

        # SBPL string literals are double-quoted with backslash escapes; a
        # grant path must never inject profile source.
        def escape(path)
          path.gsub(/["\\]/) { |char| "\\#{char}" }
        end
      end
    end
  end
end
