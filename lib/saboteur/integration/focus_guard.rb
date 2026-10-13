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
    # The test is a difference of two selections, both made by RSpec's own
    # FilterManager#prune: the examples that run now, and the examples that
    # would run if the stray focus rule were absent. Everything else RSpec
    # decides stays the same in both, so it never counts as hidden: example
    # selectors (`spec/a_spec.rb:12`) and their file-scoped priority,
    # `--tag` filters named in rspec_args, exclusions, and the :if / :unless
    # pruning of conditional examples.
    class FocusGuard
      LOCATION_KEYS = %i[locations ids].freeze

      def initialize(world:, explicit_filter_keys:)
        @world = world
        @explicit_filter_keys = explicit_filter_keys
      end

      # Raises ConfigError naming the focused examples when the focus filter
      # hides examples that would otherwise run.
      def check!
        return if stray_rules.empty?
        return if hidden_examples.empty?

        raise ConfigError, message
      end

      private

      attr_reader :world

      def filter_manager
        world.filter_manager
      end

      # Inclusion rules the suite added itself, such as the :focus rule that
      # `filter_run_when_matching :focus` installs once a fit exists.
      def stray_rules
        @stray_rules ||= begin
          rules = filter_manager.inclusions.rules
          rules.slice(*(rules.keys - LOCATION_KEYS - @explicit_filter_keys))
        end
      end

      def running_examples
        @running_examples ||= filter_manager.prune(world.all_examples)
      end

      # The selection RSpec would make without the stray rules.
      def examples_without_stray_focus
        manager = ::RSpec::Core::FilterManager.new
        manager.exclusions.rules.replace(filter_manager.exclusions.rules)
        manager.inclusions.rules.replace(filter_manager.inclusions.rules.except(*stray_rules.keys))
        manager.prune(world.all_examples)
      end

      def hidden_examples
        @hidden_examples ||= examples_without_stray_focus - running_examples
      end

      def focused_examples
        focus = ::RSpec::Core::FilterRules.new(stray_rules)
        running_examples.select { |example| focus.include_example?(example) }
      end

      def message
        total = hidden_examples.size + running_examples.size
        locations = focused_examples.map(&:location).uniq.first(5).join(", ")
        "a focus filter (#{::RSpec::Core::FilterRules.new(stray_rules).description}) narrowed the suite: " \
          "#{hidden_examples.size} of #{total} examples would not run, so the score would cover only the " \
          "ones that do (#{locations}). Remove the focus, or pass --allow-focus to run the narrowed suite anyway."
      end
    end
  end
end
