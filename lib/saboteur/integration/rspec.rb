# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Integration
    # Loads spec files once in the parent. In a child, narrows the already
    # loaded world to the requested example ids and runs it with a private
    # reporter, so nothing is printed and no status file is written.
    class RSpec < Base
      def setup
        require "rspec/core"
        ::RSpec::Core::Runner.disable_autorun!
        options = ::RSpec::Core::ConfigurationOptions.new(rspec_args)
        @runner = ::RSpec::Core::Runner.new(options)
        @runner.setup($stderr, $stdout)
        raise Error, "rspec quit while loading spec files" if world.wants_to_quit
      end

      # RSpec only adds its default "spec" path when $0 is `rspec`.
      def rspec_args
        args = Array(config.fetch("rspec_args", []))
        args.any? { |arg| !arg.start_with?("-") } ? args : args + ["spec"]
      end

      def all_tests
        groups = world.ordered_example_groups.flat_map(&:descendants)
        groups.flat_map { |group| world.filtered_examples[group] }
              .map { |example| TestCase.new(id: example.id, file: example.metadata[:rerun_file_path]) }
      end

      def test_files
        world.example_groups.map { |group| File.expand_path(group.metadata[:file_path]) }.uniq
      end

      # Runs the tests in the order given: groups by their earliest example,
      # examples by position.
      def run(ids)
        wanted = Set.new(ids)
        narrow_to(wanted)
        order_by(ids)
        configuration.fail_fast = 1
        listener = Listener.new
        passed = execute(listener)
        RunResult.new(passed: passed && listener.failed.empty?, failed_ids: listener.failed,
                      executed_ids: listener.executed, runtime: listener.runtime,
                      failure_classes: listener.failure_classes, failure_messages: listener.failure_messages)
      end

      def run_all(recorder)
        configuration.fail_fast = false
        execute(Listener.new(recorder))
      end

      private

      def world
        ::RSpec.world
      end

      def configuration
        ::RSpec.configuration
      end

      def order_by(ids)
        rank = ids.each_with_index.to_h
        example_rank = ->(example) { rank.fetch(example.id, Float::INFINITY) }
        configuration.register_ordering(:global) do |items|
          items.sort_by do |item|
            if item.is_a?(Class)
              item.descendant_filtered_examples.map(&example_rank).min || Float::INFINITY
            else
              example_rank.call(item)
            end
          end
        end
      end

      def narrow_to(wanted)
        world.filtered_examples.clear
        world.filtered_examples.default_proc = proc do |hash, group|
          hash[group] = group.examples.select { |example| wanted.include?(example.id) }
        end
        world.example_groups.flat_map(&:descendants).each(&:reset_memoized)
      end

      def execute(listener)
        reporter = ::RSpec::Core::Reporter.new(configuration)
        reporter.register_listener(listener, *Listener::EVENTS)
        groups = world.ordered_example_groups.select { |group| group.descendant_filtered_examples.any? }
        count = world.example_count(groups)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        passed = reporter.report(count) do |r|
          configuration.with_suite_hooks { groups.map { |group| group.run(r) }.all? }
        end
        listener.runtime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        passed && !world.non_example_failure
      end

      class Listener
        EVENTS = %i[example_started example_finished example_failed].freeze

        MESSAGE_LIMIT = 200

        attr_reader :executed, :failed, :failure_classes, :failure_messages
        attr_accessor :runtime

        def initialize(recorder = nil)
          @recorder = recorder
          @executed = []
          @failed = []
          @failure_classes = {}
          @failure_messages = {}
          @runtime = 0.0
        end

        def example_started(notification)
          example = notification.example
          @recorder&.test_started(example.id, File.expand_path(example.metadata[:rerun_file_path]))
        end

        def example_finished(notification)
          @executed << notification.example.id
          @recorder&.test_finished(notification.example.id)
        end

        def example_failed(notification)
          @failed << notification.example.id
          exception = notification.example.execution_result.exception
          @failure_classes[notification.example.id] = exception&.class&.name
          @failure_messages[notification.example.id] = first_line(exception&.message)
        end

        private

        def first_line(message)
          message.to_s.lines.map(&:strip).find { |line| !line.empty? }.to_s[0, MESSAGE_LIMIT]
        end
      end
    end

    register :rspec, RSpec
  end
end
