# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fiddle"
require "fiddle/import"

module Saboteur
  module Execution
    # The third hazard layer (issue #152): a mutant child restricts itself
    # with Landlock so the project tree is read-only, except the cache dir,
    # the project's tmp/ and the system temp dir. A mutant that escapes the
    # hazard guard and the canary still cannot damage the tree.
    #
    # Landlock needs no privileges and works from a multithreaded process,
    # which a mount/user namespace cannot (Ruby's timer thread makes
    # unshare(CLONE_NEWUSER) fail with EINVAL). Where the kernel predates
    # Landlock (5.13) the child runs unsandboxed, exactly as before.
    module Sandbox
      SYS_CREATE_RULESET = 444
      SYS_ADD_RULE = 445
      SYS_RESTRICT_SELF = 446
      CREATE_RULESET_VERSION = 1
      RULE_PATH_BENEATH = 1
      PR_SET_NO_NEW_PRIVS = 38
      O_PATH = 0o10000000

      # Every write-side right, so reads and execution keep working anywhere.
      BASE_RIGHTS = (1 << 1) | (1 << 4) | (1 << 5) | (1 << 6) | (1 << 7) | (1 << 8) |
                    (1 << 9) | (1 << 10) | (1 << 11) | (1 << 12)
      REFER = 1 << 13 # ABI 2 (5.19)
      TRUNCATE = 1 << 14 # ABI 3 (6.2)
      WRITE_FILE = 1 << 1

      module LibC
        extend Fiddle::Importer

        dlload "libc.so.6"
        extern "int prctl(int, long, long, long, long)"
        extern "int open(const char *, int)"
        extern "int close(int)"
        extern "void *__errno_location()"
      end

      SYSCALL = Fiddle::Function.new(
        Fiddle.dlopen("libc.so.6")["syscall"],
        [Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG],
        Fiddle::TYPE_LONG
      )

      module_function

      def linux?
        RUBY_PLATFORM.include?("linux")
      end

      # The kernel's Landlock ABI (0 when unsupported), memoized per process.
      def abi_version
        return @abi_version if defined?(@abi_version)

        @abi_version = if linux?
                         version = SYSCALL.call(SYS_CREATE_RULESET, 0, 0, CREATE_RULESET_VERSION, 0)
                         version.positive? ? version : 0
                       else
                         0
                       end
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
      def restrict!(writable:)
        ruleset = create_ruleset
        begin
          writable.each { |dir| allow(ruleset, dir, rights_mask) }
          allow(ruleset, File::NULL, WRITE_FILE)
          check("prctl(PR_SET_NO_NEW_PRIVS)") { LibC.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) }
          check("landlock_restrict_self") { SYSCALL.call(SYS_RESTRICT_SELF, ruleset, 0, 0, 0) }
        ensure
          LibC.close(ruleset)
        end
        nil
      end

      def create_ruleset
        attr = [rights_mask].pack("Q<")
        fd = SYSCALL.call(SYS_CREATE_RULESET, Fiddle::Pointer[attr], attr.bytesize, 0, 0)
        errno = last_errno
        check_fd("landlock_create_ruleset", fd, errno)
        fd
      end

      def allow(ruleset, path, rights)
        parent = LibC.open(path, O_PATH)
        errno = last_errno
        check_fd("open #{path}", parent, errno)
        attr = "#{[rights].pack('Q<')}#{[parent].pack('l<')}\0\0\0\0"
        check("landlock_add_rule #{path}") do
          SYSCALL.call(SYS_ADD_RULE, ruleset, RULE_PATH_BENEATH, Fiddle::Pointer[attr], 0)
        end
      ensure
        LibC.close(parent) if parent && parent >= 0
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
        LibC.__errno_location.to_s(4).unpack1("l!")
      end
    end
  end
end
