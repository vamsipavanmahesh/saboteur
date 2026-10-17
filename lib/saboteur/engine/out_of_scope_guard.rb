# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # The --since stop whose changed source files all sit outside the
    # include scope (#483), kept apart from the guess flow it guards.
    module OutOfScopeGuard
      private

      # Every changed source file sits outside the include scope (#483): the
      # whole-suite fallback would run the slowest possible suite against
      # zero subjects, so stop and name what the scope hid.
      def refuse_out_of_scope_changes(guess)
        return unless guess.changed.zero? && guess.out_of_scope.any?

        raise ConfigError, guess.out_of_scope_message
      end
    end
  end
end
