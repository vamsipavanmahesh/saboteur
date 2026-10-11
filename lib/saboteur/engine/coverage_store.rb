# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require "fileutils"
require "json"

module Saboteur
  class Engine
    # Returns the coverage map for a run: from the cache when every input is
    # unchanged, otherwise built by running the whole suite once in a
    # supervised child and saved.
    class CoverageStore
      CACHE_INPUTS = %w[integration require rspec_args rails tests].freeze
      LOCKFILES = %w[Gemfile.lock gems.locked].freeze
      LOG = "coverage-build.log"

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
        all = files + @integration.test_files + SuiteFiles.new(@config).files + lockfiles
        Selection::CoverageMap.cache_key(files: all.uniq, extra: inputs)
      end

      def lockfiles
        LOCKFILES.map { |file| File.join(@root, file) }.select { |file| File.file?(file) }
      end

      def build(files)
        unless Coverage.respond_to?(:state) && Coverage.state == :suspended
          raise Error, "Coverage is #{Coverage.state}; saboteur must set it up before the app loads. " \
                       "Run through the saboteur executable and disable SimpleCov for the run."
        end

        @diagnostics.inform("building coverage map (runs the whole suite once)")
        # The suite child forked next inherits this heap; pack it first, to
        # reduce later copying of shared pages.
        Execution::ForkReadiness.prepare_heap
        result = @supervisor.run(timeout: @config["coverage_timeout"]) { |writer| record(writer, files) }
        raise Error, "coverage map build stopped: #{result.detail}" if result.stopped_by
        raise Error, "coverage map build failed: #{died(result.exit_status)}" if result.payload.empty?

        data = JSON.parse(result.payload)
        raise Error, "coverage map build failed: #{data['error']}" if data["error"]

        Selection::CoverageMap.from_json(result.payload)
      end

      def died(status)
        how = if status&.signaled? then "was killed by signal #{Signal.signame(status.termsig)}"
              else "exited with status #{status&.exitstatus}"
              end
        "the suite #{how} before reporting; its output is in #{log_path.delete_prefix("#{@root}/")}"
      end

      def log_path
        File.join(@config.path("cache_dir"), LOG)
      end

      # Runs in the supervised child. The suite's output goes to a log, so a
      # child that dies without reporting can still be diagnosed.
      def record(writer, files)
        FileUtils.mkdir_p(File.dirname(log_path))
        $stdout.reopen(log_path, "w")
        $stdout.sync = true
        $stderr.reopen($stdout)
        @hooks.run(:after_fork)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        recorder = Selection::Recorder.new(files)
        recorder.start
        Kernel.srand(@config["seed"])
        passed = @integration.run_all(recorder)
        if passed == false
          raise Error, "the unchanged suite failed while building coverage. Fix the suite, then run again " \
                       "with seed #{@config['seed']}."
        end
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
