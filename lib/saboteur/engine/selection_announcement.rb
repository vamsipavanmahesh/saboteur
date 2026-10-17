# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Nothing to mutate is the run's outcome, already stated by the
    # "0 subjects, 0 mutants" summary: note it once (#468). As a report
    # warning it would print again at the end of the run, and a zero-subject
    # run ends right away, so the repeat reads like a second failure.
    module SelectionAnnouncement
      # Name the files needing no spec, stop on spec-less files, then say
      # which specs the run scopes to (or why nothing mutates).
      def announce_guess(guess)
        @diagnostics.inform(guess.subjectless_message(since: config["since"])) if guess.subjectless.any?
        inform_skipped_specs(guess)
        raise ConfigError, guess.unmatched_message if guess.unmatched.any?

        announce_selection(guess)
      end

      private

      def announce_selection(guess)
        if guess.changed.zero? || guess.specs.any?
          @diagnostics.announce(selection_message(guess))
        else
          @diagnostics.inform(selection_message(guess))
        end
      end

      # A spec file the diff touched that cannot run is named, also before a
      # stop on an unmatched file: --test, the way out, never reads the diff.
      def inform_skipped_specs(guess) = (@diagnostics.inform(guess.skipped_message) if guess.skipped_specs.any?)

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

      # Stop before boot: name the spec-less files and the ways out. The
      # hinted spec paths are the conventional ones - they do not exist (that
      # is why the files are unmatched), so the message never prints them as
      # a runnable --test command, and it never reconstructs the source
      # scope: the user appends --test or --all to their own command. The
      # example is still shell-safe: the ref is user input, so it is quoted
      # and pinned to the flag with = (a ref like "-x" must not become a
      # switch).
      def scope_to_guesses(guess)
        # The guesses now stand as explicit tests, like --test. guess_tests is
        # dropped rather than set to false: an explicit false is the deprecated
        # opt-out and would warn.
        @config = config.with({ "tests" => guess.specs }, except: ["guess_tests"])
        @guessed_tests = guess.specs
        guess.scope_message(since: config["since"])
      end
    end
  end
end
