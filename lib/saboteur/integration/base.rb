# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Integration
    TestCase = Data.define(:id, :file)
    # executed_ids: tests that actually ran, so the runner can tell a broken
    # filter (nothing ran, every mutant "survives") from a real pass.
    # failure_classes: the exception class name each failed test died with,
    # so a kill by a failed assertion can be told from a kill by a crash.
    # failure_messages: the first line of each failure, so a verdict that
    # does not hold up can say why the test failed.
    RunResult = Data.define(:passed, :failed_ids, :executed_ids, :runtime, :failure_classes, :failure_messages) do
      def initialize(passed:, failed_ids:, executed_ids:, runtime:, failure_classes: {}, failure_messages: {})
        super
      end
    end

    REGISTRY = {} # rubocop:disable Style/MutableConstant

    def self.register(name, klass)
      REGISTRY[name.to_s] = klass
    end

    def self.fetch(name)
      REGISTRY.fetch(name.to_s) { raise Saboteur::Error, "unknown integration: #{name}" }
    end

    # Contract every test framework adapter implements.
    #
    # Lifecycle: #setup runs once in the parent after boot and loads test files
    # without running any test. #run and #run_all are called inside a forked
    # child; they must not exit the process and must report by return value,
    # not by printing.
    class Base
      attr_reader :config

      def initialize(config)
        @config = config
      end

      def setup
        raise NotImplementedError
      end

      # @return [Array<TestCase>]
      def all_tests
        raise NotImplementedError
      end

      # Runs the given tests, stopping at the first failure.
      # @param ids [Array<String>] ids from #all_tests
      # @return [RunResult]
      def run(_ids)
        raise NotImplementedError
      end

      # Runs every test, calling recorder.test_started(id, file) before and
      # recorder.test_finished(id) after each one. Used to build the coverage map.
      def run_all(_recorder)
        raise NotImplementedError
      end

      # Checks the unchanged suite in a fresh child. Existing adapters can
      # use their selected-test runner; adapters may override to retain full
      # suite ordering and report every executed test.
      def run_baseline(seed:)
        Kernel.srand(seed)
        run(all_tests.map(&:id))
      end

      # Files whose content decides which tests exist (for the cache key).
      def test_files
        []
      end
    end
  end
end

require_relative "rspec"
