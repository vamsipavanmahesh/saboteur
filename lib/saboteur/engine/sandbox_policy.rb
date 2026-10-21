# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Saboteur
  class Engine
    # Decides what each mutant child's Landlock sandbox grants (#152), and
    # notes once per run when the kernel cannot honor it.
    class SandboxPolicy
      def initialize(config:, root:, diagnostics:)
        @config = config
        @root = root
        @diagnostics = diagnostics
      end

      # The third C1 layer (#152): each mutant child makes the project tree
      # read-only except tmp/ and the system temp dir - the cache dir stays
      # read-only too, so a mutant cannot delete the baseline, the reports
      # or other children's logs; its own log arrives as an inherited open
      # descriptor (#234). The
      # claim needs Landlock ABI 3 (Linux 6.2+): earlier ABIs cannot restrict
      # truncate(), so the run degrades honestly - children run with the
      # guard and canary only, noted once - unless c.sandbox = "strict",
      # which refuses instead.
      def hook
        return nil unless @config["sandbox"]
        return seatbelt_hook if @config["sandbox"] == "seatbelt" && Execution::Seatbelt.darwin?

        abi = sandbox_abi
        return restrict_hook if abi >= 3

        if @config["sandbox"] == "strict"
          raise Error, "sandbox is strict but #{self.class.sandbox_gap(abi)}; refusing to run without the promised " \
                       "sandbox - set c.sandbox = true to run degraded, or false to opt out"
        end
        # Once, through the report's warnings only: warn + inform printed the
        # same line twice (D's review, #178).
        unless @sandbox_note_given
          @sandbox_note_given = true
          @diagnostics.warn(degraded_note(abi))
        end
        nil
      end

      # ENOSYS/EOPNOTSUPP are a clean "no Landlock here"; any other probe
      # error (EPERM under seccomp, ...) must not silently run unsandboxed.
      def sandbox_abi
        Execution::Sandbox.abi_version
      rescue SystemCallError => e
        raise Error, "sandbox is on but the Landlock probe failed (#{e.message}); refusing to run " \
                     "unsandboxed - set c.sandbox = false to proceed without it"
      end

      def self.sandbox_gap(abi)
        if abi.zero?
          # Landlock is Linux-only: on macOS there is no kernel to upgrade,
          # so name the platform instead of a Linux version (#667).
          return "macOS has no Landlock" if Execution::Seatbelt.darwin?

          return "this kernel lacks Landlock (needs Linux 6.2+)"
        end

        "this kernel's Landlock ABI is #{abi} but ABI 3 (Linux 6.2+) is needed to restrict truncate()"
      end

      # The degraded-run note: on macOS the gap is permanent, so point at
      # the Seatbelt opt-in; on Linux the kernel wording stands alone
      # (#667). Severity stays a warning - degrading confinement is never
      # routine.
      def degraded_note(abi)
        gap = self.class.sandbox_gap(abi)
        tail = "children run with the hazard guard and canary only"
        unless Execution::Seatbelt.darwin?
          return "sandbox is on but #{gap}; #{tail}\n  " \
                 "Fix: run on Linux 6.2+ (Landlock ABI 3) for full confinement, " \
                 "or set c.sandbox = false to run unsandboxed"
        end

        "sandbox is on but #{gap}; #{tail}\n  " \
          "Fix: opt into the macOS sandbox with c.sandbox = \"seatbelt\" " \
          "(docs/guides/macos-seatbelt-sandbox.md), or set c.sandbox = false to silence this"
      end

      def restrict_hook
        writable = sandbox_writable_dirs
        ->(keep_fds) { Execution::Sandbox.restrict!(writable: writable, keep_fds: keep_fds) }
      end

      # c.sandbox = "seatbelt" (the macOS opt-in, #436): the probe decides.
      # Confine when Seatbelt truly enforces; a clean "no Seatbelt here"
      # degrades to the guard and canary with a one-time note; anything
      # else - an errored probe, or an API claiming success its profile
      # cannot prove - refuses the run, exactly like the Landlock probe
      # (#178): opting into a sandbox must never buy silent confinement
      # theatre. Fail-closed lives one layer down too: a child whose
      # profile refuses to apply raises instead of running the mutant.
      def seatbelt_hook
        case (verdict = Execution::Seatbelt.probe)
        when :ok
          writable = sandbox_writable_dirs
          ->(keep_fds) { Execution::Seatbelt.restrict!(writable: writable, keep_fds: keep_fds) }
        when :unavailable
          seatbelt_note("this macOS lacks Seatbelt")
          nil
        else
          raise Error, "sandbox is \"seatbelt\" but the Seatbelt probe #{verdict_description(verdict)}; refusing to " \
                       "run unsandboxed - set c.sandbox = true to run with the hazard guard and canary only, " \
                       "or false to opt out"
        end
      end

      def verdict_description(verdict)
        case verdict
        when :unenforced then "reported a profile that did not enforce - a macOS update may have changed it (#436)"
        else "failed (#{verdict}) - #436 tracks the deprecation"
        end
      end

      def seatbelt_note(reason)
        return if @sandbox_note_given

        @sandbox_note_given = true
        @diagnostics.warn("sandbox is \"seatbelt\" but #{reason}; children run with the hazard guard and " \
                          "canary only\n  Fix: set c.sandbox = true to use Landlock instead, " \
                          "or c.sandbox = false to opt out")
      end

      # c.sandbox_writable adds the dirs a suite genuinely needs (db/, log/,
      # ...): without a grant, writes there fail with EACCES in the child.
      # Only the user grants are created: the project tmp is granted when it
      # already exists, never made for it (#236).
      def sandbox_writable_dirs
        user_dirs = @config["sandbox_writable"].map { |dir| File.expand_path(dir, @root) }
        user_dirs.each { |dir| FileUtils.mkdir_p(dir) }
        tmp = File.join(@root, "tmp")
        dirs = Dir.exist?(tmp) ? [tmp] + user_dirs : user_dirs
        real = (dirs.map { |dir| File.realpath(dir) } + [File.realpath(Dir.tmpdir)]).uniq
        check_sandbox_write_set(real, user_dirs.map { |dir| File.realpath(dir) })
        real
      end

      # The effective write set - every grant realpath'd, the project tmp
      # and the system temp dir included - must not contain the project
      # root: a tmp symlink or a checkout inside the system temp dir would
      # otherwise leave the whole tree writable without a word.
      # c.sandbox = "strict" refuses: strict guards the effective
      # policy, not only the kernel ABI. A user grant containing another
      # grant only makes the narrower one redundant, so that stays a warning.
      def check_sandbox_write_set(all_dirs, user_dirs)
        holder = all_dirs.find { |dir| path_contains?(dir, @root) }
        if holder
          message = "narrow the sandbox grant #{holder} so it no longer contains the project root\n  " \
                    "sandbox grant #{holder} contains the project root; mutant children can write the whole tree"
          raise Error, %(#{message} - refusing under c.sandbox = "strict") if @config["sandbox"] == "strict"

          @diagnostics.warn(message)
        end
        user_dirs.each do |dir|
          (all_dirs - [dir]).each do |other|
            next unless path_contains?(dir, other)

            safe_other = Text.display_safe(other)
            @diagnostics.warn("drop the redundant sandbox grant #{safe_other}\n  " \
                              "sandbox grant #{Text.display_safe(dir)} contains the granted dir #{safe_other}; " \
                              "the narrower grant is redundant")
          end
        end
      end

      # Both sides are realpath'd, so a plain "#{dir}/" prefix test would miss
      # dir == "/" (every path is under it; "//" prefixes nothing).
      def path_contains?(dir, path)
        return true if dir == "/"

        path == dir || path.start_with?("#{dir}/")
      end
    end
  end
end
