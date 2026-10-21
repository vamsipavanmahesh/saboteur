# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # The option map `saboteur help` prints per command. run, pr and audit
    # share the run parser: the presets take every run option.
    module HelpOptions
      def option_lines
        run = parser.summarize
        { "run" => run, "pr" => run, "audit" => run, "doctor" => doctor_parser.summarize,
          "baseline" => baseline_parser.summarize, "badge" => badge_parser.summarize,
          "trend" => trend_parser.summarize, "survivors" => survivors_parser.summarize }
      end
    end
  end
end
