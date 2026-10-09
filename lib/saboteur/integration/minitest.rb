# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Integration
    # Loads test files once in the parent with Minitest's at_exit autorun
    # disabled. Test ids are "Klass#test_name". Runs tests one by one with
    # Runnable#run, bypassing Minitest's reporters.
    class Minitest < Base
      DEFAULT_TEST_FILES = ["test/**/*_test.rb", "test/**/test_*.rb"].freeze

      def setup
        require "minitest"
        # minitest/autorun installs an at_exit hook that would run the whole
        # suite when the parent exits. Mark it as installed so it never is.
        ::Minitest.class_variable_set(:@@installed_at_exit, true) # rubocop:disable Style/ClassVars
        ::Minitest.seed ||= Random.new_seed % 0xFFFF
        Array(config.fetch("test_load_path", ["test"])).each do |path|
          $LOAD_PATH.unshift(File.expand_path(path)) unless $LOAD_PATH.include?(File.expand_path(path))
        end
        test_files.each { |file| require file }
      end

      def test_files
        patterns = Array(config.fetch("test_files", nil) || DEFAULT_TEST_FILES)
        patterns.flat_map { |pattern| Dir.glob(pattern) }.map { |file| File.expand_path(file) }.uniq.sort
      end

      def all_tests
        runnables.flat_map do |klass|
          klass.runnable_methods.map do |name|
            TestCase.new(id: "#{klass.name}##{name}", file: klass.instance_method(name).source_location&.first)
          end
        end
      end

      def run(ids)
        executed = []
        failed = []
        started = monotonic
        ids.each do |id|
          executed << id
          unless passes?(id)
            failed << id
            break
          end
        end
        RunResult.new(passed: failed.empty?, failed_ids: failed, executed_ids: executed,
                      runtime: monotonic - started)
      end

      def run_all(recorder)
        all_tests.each do |test|
          recorder.test_started(test.id, test.file)
          passes?(test.id)
          recorder.test_finished(test.id)
        end
      end

      private

      def runnables
        ::Minitest::Runnable.runnables.select { |klass| klass.name && !klass.runnable_methods.empty? }
      end

      def passes?(id)
        class_name, _, method_name = id.rpartition("#")
        klass = Object.const_get(class_name)
        result = klass.new(method_name).run
        result.passed? || result.skipped?
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    register :minitest, Minitest
  end
end
