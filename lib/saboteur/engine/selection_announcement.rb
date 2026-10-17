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

      def selection_message(guess)
        if guess.changed.zero?
          target = config["since"] ? "no changed source file" : "no source file"
          "inferred specs: #{target} to infer a spec for, so the whole suite runs"
        elsif guess.specs.empty?
          guess.no_specs_message(since: config["since"])
        else
          scope_to_guesses(guess)
        end
      end

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
