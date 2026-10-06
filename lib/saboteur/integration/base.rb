# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Integration
    TestCase = Data.define(:id, :location)
    RunResult = Data.define(:passed, :failed_ids, :runtime)

    REGISTRY = {} # rubocop:disable Style/MutableConstant

    def self.register(name, klass)
      REGISTRY[name.to_s] = klass
    end

    def self.fetch(name)
      REGISTRY.fetch(name.to_s) { raise Saboteur::Error, "unknown integration: #{name}" }
    end

    # Contract every test framework adapter implements.
    #
    # Lifecycle: #setup runs once in the parent after boot and loads test files.
    # #run is called inside a forked child; it must not exit the process and must
    # report results by return value, not by printing.
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

      # @param ids [Array<String>] ids from #all_tests
      # @return [RunResult]
      def run(_ids)
        raise NotImplementedError
      end
    end
  end
end

require_relative "rspec"
require_relative "minitest"
