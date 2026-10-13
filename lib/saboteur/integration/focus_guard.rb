# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Integration
    # Refuses a suite that a focus filter has narrowed without the user asking
    # for it. With `filter_run_when_matching :focus`, one stray `fit` makes
    # RSpec skip every other example. The baseline stays green and the score
    # then describes only the focused examples, with no sign that the rest
    # never ran.
    #
    # Filters named on purpose in rspec_args (`--tag`) and example selectors
    # (`spec/a_spec.rb:12`) are not focus filters and are left alone.
    class FocusGuard
      LOCATION_KEYS = %i[locations ids].freeze

      def initialize(world:, explicit_filter_keys:)
        @world = world
        @explicit_filter_keys = explicit_filter_keys
      end

      # Raises ConfigError naming the focused examples when focus has hidden
      # other examples.
      def check!
        return unless hidden_example_count.positive?

        raise ConfigError, message
      end

      private

      attr_reader :world

      def focus_rules
        @focus_rules ||= begin
          rules = world.filter_manager.inclusions.rules
          keys = rules.keys - LOCATION_KEYS - @explicit_filter_keys
          ::RSpec::Core::FilterRules.new(rules.slice(*keys))
        end
      end

      def exclusions
        world.filter_manager.exclusions
      end

      def focused_examples
        return [] if focus_rules.rules.empty?

        world.all_examples.select { |example| focus_rules.include_example?(example) }
      end

      # Examples that only the focus filter keeps from running: not focused,
      # and not skipped by an exclusion the suite chose.
      def hidden_example_count
        return 0 if focused_examples.empty?

        world.all_examples.count do |example|
          !focus_rules.include_example?(example) && !exclusions.include_example?(example)
        end
      end

      def message
        locations = focused_examples.map(&:location).uniq.first(5).join(", ")
        "a focus filter (#{focus_rules.description}) narrowed the suite: #{hidden_example_count} of " \
          "#{world.all_examples.size} examples would not run, so the score would cover only the focused " \
          "ones (#{locations}). Remove the focus, or pass --allow-focus to run the narrowed suite anyway."
      end
    end
  end
end
