# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../help"
require_relative "../reporter/palette"
require_relative "../mutation_source/operator_explain"

module Saboteur
  class CLI
    # Shared rendering for `saboteur explain <operator>` (#1097): the
    # curated definition, a before/after example and survive/kill guidance
    # for one operator, so a survivor's operator can be understood and
    # targeted without leaving the terminal.
    module ExplainCommand
      private

      def explain_command
        consume_color_options
        name = @argv.shift
        raise UsageError, "usage: saboteur explain <operator>" if name.nil?

        entry = MutationSource::OperatorExplain.for(name)
        if entry.nil?
          @err.puts("saboteur: unknown operator: #{name}")
          suggestion = MutationSource::OperatorRegistry.suggestion(name)
          @err.puts("saboteur: #{suggestion}") unless suggestion.empty?
          @err.puts("saboteur: operators: #{MutationSource::OperatorRegistry::DESCRIPTIONS.keys.join(', ')}")
          return EXIT_USAGE
        end

        @out.puts(render_explain(entry, palette: Reporter::Palette.for(@out, mode: @color || :auto)))
        EXIT_OK
      rescue UsageError => e
        @err.puts("saboteur: #{e.message}")
        EXIT_USAGE
      end

      def render_explain(entry, palette: Reporter::Palette.new(enabled: false))
        original, replacement = entry.example.split(" -> ")
        [
          "#{palette.paint(:head, 'Operator:')} #{entry.name}",
          "#{palette.paint(:head, 'Definition:')} #{entry.definition}",
          palette.paint(:head, "Example:"),
          "  #{palette.paint(:fail, "- #{original}")}",
          "  #{palette.paint(:pass, "+ #{replacement}")}",
          "#{palette.paint(:warn, 'Survives when:')} #{entry.survives}",
          "#{palette.paint(:info, 'Kill it with:')} #{entry.kill}"
        ].join("\n")
      end
    end
  end
end
