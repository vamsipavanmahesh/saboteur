# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fiddle"
require "fiddle/import"

module Saboteur
  module Execution
    # The third hazard layer (issue #152): a mutant child restricts itself
    # with Landlock so the project tree is read-only, except the cache dir,
    # the project's tmp/ and the system temp dir.
    #
    # Landlock needs no privileges and works from a multithreaded process,
    # which a mount/user namespace cannot (Ruby's timer thread makes
    # unshare(CLONE_NEWUSER) fail with EINVAL). What it guarantees depends
    # on the kernel's Landlock ABI: ABI 3 (Linux 6.2) also restricts
    # truncate(); on ABI 1-2 (Linux 5.13-6.1) a mutant can still truncate
    # project files, and the run notes that once. Where the kernel has no
    # Landlock at all (before 5.13) the child runs unsandboxed, exactly as
    # before - and a probe that errors for any other reason refuses the
    # run instead of silently dropping the sandbox. Landlock restricts the
    # filesystem only: network, sockets and IPC are never covered.
    #
    # libc is dlopened lazily on first use, and first use is always behind
    # the linux? gate: requiring this file (which saboteur.rb does
    # unconditionally) must stay inert on macOS and non-glibc Linux, where
    # libc.so.6 does not exist (#178).
    module Sandbox
      SYS_CREATE_RULESET = 444
      SYS_ADD_RULE = 445
      SYS_RESTRICT_SELF = 446
      CREATE_RULESET_VERSION = 1
      RULE_PATH_BENEATH = 1
      PR_SET_NO_NEW_PRIVS = 38
      O_PATH = 0o10000000
      O_ACCMODE = 0o3
      F_GETFL = 3

      # Every write-side right, so reads and execution keep working anywhere.
      BASE_RIGHTS = (1 << 1) | (1 << 4) | (1 << 5) | (1 << 6) | (1 << 7) | (1 << 8) |
                    (1 << 9) | (1 << 10) | (1 << 11) | (1 << 12)
      REFER = 1 << 13 # ABI 2 (5.19)
      TRUNCATE = 1 << 14 # ABI 3 (6.2)
      WRITE_FILE = 1 << 1

      # A probe answered with these says Landlock is genuinely absent.
      UNSUPPORTED_ERRNOS = [Errno::ENOSYS::Errno, Errno::EOPNOTSUPP::Errno].freeze

      module_function

      def linux?
        RUBY_PLATFORM.include?("linux")
      end

      # The kernel's Landlock ABI (0 when unsupported), memoized per process.
      def abi_version
        return @abi_version if defined?(@abi_version)
        return @abi_version = 0 unless linux?

        version = LibC.syscall_fn.call(SYS_CREATE_RULESET, 0, 0, CREATE_RULESET_VERSION, 0)
        errno = last_errno
        @abi_version = probe_abi(version, errno)
      rescue Fiddle::DLError
        # No usable libc (an unusual musl/ldso layout): the sandbox cannot
        # be built here, so degrade to the unsandboxed note, not a crash.
        @abi_version = 0
      end

      # A positive answer is the ABI. ENOSYS/EOPNOTSUPP mean the kernel has
      # no Landlock to give: run unsandboxed, noted once. Anything else
      # (EPERM under a seccomp policy, ...) means the kernel is there but
      # refused - fail closed rather than run without the promised sandbox.
      def probe_abi(version, errno)
        return version if version.positive?
        return 0 if UNSUPPORTED_ERRNOS.include?(errno)

        raise SystemCallError.new("landlock_create_ruleset probe", errno)
      end

      def available?
        abi_version >= 1
      end

      # The rights mask this kernel understands; newer rights are gated by
      # the probed ABI so old kernels do not reject the ruleset as invalid.
      def rights_mask
        mask = BASE_RIGHTS
        mask |= REFER if abi_version >= 2
        mask |= TRUNCATE if abi_version >= 3
        mask
      end

      # Called at the top of a mutant child. Irreversible and fail-closed: a
      # child whose sandbox cannot be fully built must not run the mutant.
      # keep_fds: descriptors the child still needs after restricting (its
      # report pipe to the parent).
      def restrict!(writable:, keep_fds: [])
        InheritedFds.close_writable_files(writable, keep_fds)
        ruleset = create_ruleset
        begin
          writable.each { |dir| allow(ruleset, dir, rights_mask) }
          allow(ruleset, File::NULL, WRITE_FILE)
          check("prctl(PR_SET_NO_NEW_PRIVS)") { LibC.prctl_fn.call(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) }
          check("landlock_restrict_self") { LibC.syscall_fn.call(SYS_RESTRICT_SELF, ruleset, 0, 0, 0) }
        ensure
          LibC.close_fn.call(ruleset)
        end
        nil
      end

      def create_ruleset
        attr = [rights_mask].pack("Q<")
        fd = LibC.syscall_fn.call(SYS_CREATE_RULESET, Fiddle::Pointer[attr], attr.bytesize, 0, 0)
        errno = last_errno
        check_fd("landlock_create_ruleset", fd, errno)
        fd
      end

      def allow(ruleset, path, rights)
        parent = LibC.open_fn.call(path, O_PATH)
        errno = last_errno
        check_fd("open #{path}", parent, errno)
        attr = "#{[rights].pack('Q<')}#{[parent].pack('l<')}\0\0\0\0"
        check("landlock_add_rule #{path}") do
          LibC.syscall_fn.call(SYS_ADD_RULE, ruleset, RULE_PATH_BENEATH, Fiddle::Pointer[attr], 0)
        end
      ensure
        LibC.close_fn.call(parent) if parent && parent >= 0
      end

      # Landlock only gates opens after restrict: an already open writable
      # file keeps writing through its descriptor. Close every inherited
      # regular-file descriptor open for writing outside the granted dirs.
      # Sockets, pipes and anonymous inodes have no path and are untouched.
      module InheritedFds
        module_function

        # stdio (0/1/2) is swept like any other descriptor: a terminal,
        # pipe or /dev/null is not a regular file and stays, but stdio
        # redirected to a writable regular file outside the grants is a
        # write channel Landlock cannot gate, so it is closed.
        def close_writable_files(writable, keep_fds)
          Dir.children("/proc/self/fd").each do |entry|
            descriptor = entry.to_i
            next if keep_fds.include?(descriptor)

            sweep_fd(descriptor, File.join("/proc/self/fd", entry), writable)
          end
          nil
        end

        # Fail closed throughout: a descriptor whose target or flags cannot
        # be read may be a writable file we cannot see, so it is closed
        # rather than skipped. Deleted files still stat through the fd (the
        # inode lives until the last descriptor closes), so they are swept
        # on their stripped path.
        def sweep_fd(descriptor, link, writable)
          target = File.readlink(link)
          stat = File.stat(link)
          return unless stat.file?

          granted = target.delete_suffix(" (deleted)")
          # readlink targets arrive tagged with default_external, so under
          # LANG=C a non-ASCII target compared against a UTF-8 grant pattern
          # raises Encoding::CompatibilityError before any test runs (CI #272).
          # Compare bytes.
          target_bytes = granted.b
          return if writable.any? { |dir| target_bytes == dir.b || target_bytes.start_with?(dir.b + "/") } # rubocop:disable Style/StringConcatenation -- interpolation with a BINARY part raises on high bytes

          flags = LibC.fcntl_fn.call(descriptor, F_GETFL, 0)
          return close_fd(descriptor) if flags.negative?
          return if flags.nobits?(O_ACCMODE) # O_RDONLY

          close_fd(descriptor)
        rescue SystemCallError
          begin
            close_fd(descriptor)
          rescue IOError, SystemCallError
            nil # the descriptor raced away; nothing left to close
          end
        end

        # Close through the owning Ruby IO when there is one: a raw close
        # leaves the IO object holding a dead fd, whose number a later open
        # recycles - and the stale IO's finalizer would then close the NEW
        # file (seen as corrupted writes in the spec suite).
        def close_fd(descriptor)
          owner = ObjectSpace.each_object(IO).find do |io|
            !io.closed? && io.fileno == descriptor
          rescue IOError
            false
          end
          owner ? owner.close : LibC.close_fn.call(descriptor)
        end
      end

      def check(what)
        result = yield
        return if result.zero?

        raise SystemCallError.new(what, last_errno)
      end

      def check_fd(what, handle, errno)
        raise SystemCallError.new(what, errno) if handle.negative?
      end

      # Read errno before anything else can clobber it: any Ruby allocation
      # between the failed call and this read can reset it to 0.
      def last_errno
        LibC.errno_location_fn.call.to_s(4).unpack1("i") # errno is an int, not a long (LP64)
      end

      # Every libc touchpoint, each built on first call - never at require
      # time, so loading this file stays inert off glibc/Linux.
      module LibC
        module_function

        # glibc's soname first, then musl's (arch-qualified), then the
        # process global symbol table: a musl system has no libc.so.6, but
        # its loader already mapped the C library Ruby is linked against,
        # and Fiddle::Handle::DEFAULT resolves symbols from there.
        def handle
          @handle ||= libc_candidates.lazy.map { |name| try_dlopen(name) }.find(&:itself) ||
                      Fiddle::Handle::DEFAULT
        end

        def libc_candidates
          arch = RbConfig::CONFIG["host_cpu"]
          ["libc.so.6", "libc.musl-#{arch}.so.1", "ld-musl-#{arch}.so.1"]
        end

        def try_dlopen(name)
          Fiddle.dlopen(name)
        rescue Fiddle::DLError
          nil
        end

        def syscall_fn
          @syscall_fn ||= Fiddle::Function.new(
            handle["syscall"],
            [Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG],
            Fiddle::TYPE_LONG
          )
        end

        def prctl_fn
          @prctl_fn ||= Fiddle::Function.new(
            handle["prctl"],
            [Fiddle::TYPE_INT, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG],
            Fiddle::TYPE_INT
          )
        end

        def open_fn
          @open_fn ||=
            Fiddle::Function.new(handle["open"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
        end

        def close_fn
          @close_fn ||= Fiddle::Function.new(handle["close"], [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
        end

        def fcntl_fn
          @fcntl_fn ||= Fiddle::Function.new(
            handle["fcntl"], [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_LONG], Fiddle::TYPE_INT
          )
        end

        def errno_location_fn
          @errno_location_fn ||= Fiddle::Function.new(handle["__errno_location"], [], Fiddle::TYPE_VOIDP)
        end
      end
    end
  end
end
