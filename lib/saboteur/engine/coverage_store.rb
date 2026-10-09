# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require "json"

module Saboteur
  class Engine
    # Returns the coverage map for a run: from the cache when every input is
    # unchanged, otherwise built by running the whole suite once in a
    # supervised child and saved.
    class CoverageStore
      CACHE_INPUTS = %w[integration require rspec_args rails].freeze
      TEST_FILES = "spec/**/*.rb"
      PROJECT_FILES = %w[Gemfile.lock gems.locked .rspec .rspec-local].freeze

      def initialize(config:, integration:, hooks:, supervisor:, diagnostics:)
        @config = config
        @integration = integration
        @hooks = hooks
        @supervisor = supervisor
        @diagnostics = diagnostics
        @root = File.realpath(config.root)
      end

      def fetch(files)
        path = File.join(@config.path("cache_dir"), "coverage-#{cache_key(files)}.json")
        cached = @config["cache"] ? Selection::CoverageMap.load(path) : nil
        return cached if cached

        map = build(files)
        map.save(path)
        map
      end

      private

      def cache_key(files)
        inputs = JSON.generate(CACHE_INPUTS.to_h { |key| [key, @config[key]] })
        inputs_files = files + @integration.test_files + test_support_files + boot_files + project_files
        Selection::CoverageMap.cache_key(files: inputs_files.uniq, extra: inputs)
      end

      # Helpers and support code shape which test runs which line as much as
      # the example files do, so every Ruby file under the test roots counts.
      def test_support_files
        Dir.glob(TEST_FILES, base: @root).map { |file| File.join(@root, file) }
      end

      # Boot files and hook files run before any test and can change what
      # each test executes.
      def boot_files
        (@config["require"] + @config["hooks"]).map do |file|
          path = File.expand_path(file, @root)
          File.file?(path) ? path : "#{path}.rb"
        end
      end

      def project_files
        PROJECT_FILES.map { |file| File.join(@root, file) }.select { |file| File.file?(file) }
      end

      def build(files)
        unless Coverage.respond_to?(:state) && Coverage.state == :suspended
          raise Error, "Coverage is #{Coverage.state}; saboteur must set it up before the app loads. " \
                       "Run through the saboteur executable and disable SimpleCov for the run."
        end

        @diagnostics.inform("building coverage map (runs the whole suite once)")
        result = @supervisor.run(timeout: @config["coverage_timeout"]) { |writer| record(writer, files) }
        raise Error, "coverage map build stopped: #{result.detail}" if result.stopped_by

        data = JSON.parse(result.payload.empty? ? '{"error":"coverage child died"}' : result.payload)
        raise Error, "coverage map build failed: #{data['error']}" if data["error"]

        Selection::CoverageMap.from_json(result.payload)
      end

      # Runs in the supervised child.
      def record(writer, files)
        $stdout.reopen(File::NULL, "w")
        $stderr.reopen($stdout)
        @hooks.run(:after_fork)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        recorder = Selection::Recorder.new(files)
        recorder.start
        @integration.run_all(recorder)
        build_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        writer.write(recorder.result(build_seconds: build_seconds).to_json)
        writer.close
      rescue Exception => e # rubocop:disable Lint/RescueException
        writer.write(JSON.generate(error: "#{e.class}: #{e.message}"))
        exit!(1)
      end
    end
  end
end
