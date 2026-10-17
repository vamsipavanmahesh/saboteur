# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Nothing to mutate is the run's outcome, already stated by the
    # "0 subjects, 0 mutants" summary: note it once (#468). As a report
    # warning it would print again at the end of the run, and a zero-subject
    # run ends right away, so the repeat reads like a second failure.
    module SelectionAnnouncement
      private

      def announce_selection(guess)
        if guess.changed.zero? || guess.specs.any?
          @diagnostics.announce(selection_message(guess))
        else
          @diagnostics.inform(selection_message(guess))
        end
      end
    end
  end
end
