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
        require "fiddle"
        require "fiddle/import" if with_import
      rescue LoadError
        raise Error, MESSAGE
      end
    end
  end
end
