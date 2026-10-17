# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Reporting and stop/warn policy for diff files no spec maps to (#370).
    module UnmappedFiles
      private

      def report_unmapped(guess)
        @diagnostics.inform(guess.subjectless_message(since: config["since"])) if guess.subjectless.any?
        inform_skipped_specs(guess)
        stop_or_warn_unmapped(guess)
      end

      # A --since run with a partial mapping runs the mapped subset with a
      # loud warning per unmapped file (#370); a full run and a zero guess
      # keep the hard stop.
      def stop_or_warn_unmapped(guess)
        return if guess.unmatched.empty?
        raise ConfigError, guess.unmatched_message if !config["since"] || guess.specs.empty?

        guess.unmatched.each { |file| @diagnostics.announce(guess.unmatched_warning(file)) }
      end
    end
  end
end
