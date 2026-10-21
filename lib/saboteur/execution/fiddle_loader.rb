# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # The one guarded door for fiddle (#639). Ruby ships fiddle itself - a
    # default gem on 3.x, a bundled gem from 4.0 - so a run never needs to
    # compile it, and a box where it cannot load has a broken Ruby or a
    # missing Gemfile line, not a reason to run mutants without the sandbox
    # layers. Every load goes through here and a failure REFUSES with the
    # fixes, instead of a bundler-time source build dying on missing ffi.h.
    module FiddleLoader
      MESSAGE = "saboteur cannot load fiddle, which Ruby normally includes " \
                "(a default gem on Ruby 3.x, a bundled gem on Ruby 4.0+), " \
                "and refuses to run without its sandbox layers. Fix one of: " \
                "reinstall Ruby so its shipped fiddle returns; " \
                "run `gem install fiddle`; " \
                "add `gem \"fiddle\"` to the Gemfile (required on Ruby 4.0+); " \
                "or install the libffi headers (libffi-dev on Debian/Ubuntu, " \
                "libffi-devel on Fedora/RHEL) and reinstall fiddle."

      # Loads fiddle (plus fiddle/import for the one caller using its
      # mixin). require is idempotent, so every touchpoint asks again for
      # free. A LoadError means the sandbox layers cannot work: REFUSE -
      # the error propagates, it is never downgraded to a warning.
      def self.require_fiddle!(with_import: false)
        quietly do
          require "fiddle"
          require "fiddle/import" if with_import
        end
      rescue LoadError
        raise Error, MESSAGE
      end

      # Ruby 3.4 prints "fiddle was loaded from the standard library, but
      # will no longer be part of the default gems" on this require when the
      # Gemfile does not name it. The notice is about the user's Gemfile, not
      # a saboteur fault, and Ruby 4.0 refuses the load outright (MESSAGE
      # says why), so only that one notice is dropped, only during this
      # require (#1226).
      NOTICE = "fiddle was loaded from the standard library"

      module NoticeFilter
        def warn(message, **)
          return if Thread.current[:saboteur_fiddle_require] && message.include?(NOTICE)

          super
        end
      end
      Warning.singleton_class.prepend(NoticeFilter)

      def self.quietly
        previous = Thread.current[:saboteur_fiddle_require]
        Thread.current[:saboteur_fiddle_require] = true
        yield
      ensure
        Thread.current[:saboteur_fiddle_require] = previous
      end
    end
  end
end
