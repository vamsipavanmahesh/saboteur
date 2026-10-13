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

      def initialize(config:, integration:, hooks:, supervisor:, diagnostics:, load_lines: {})
        @config = config
        @integration = integration
        @hooks = hooks
        @supervisor = supervisor
        @diagnostics = diagnostics
        @load_lines = load_lines
        @root = File.realpath(config.root)
      end

      def fetch(files)
        path = File.join(@config.path("cache_dir"), "coverage-#{cache_key(files)}.json")
        cached = @config["cache"] ? Selection::CoverageMap.load(path) : nil
        return refuse_empty_map(cached, files) if cached

        map = refuse_empty_map(build(files), files)
        map.save(path)
        File.write(File.join(@config.path("cache_dir"), "preview.json"),
                   JSON.generate(path: path, fingerprint: RunFingerprint.new(config: @config).snapshot.digest))
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

        scope = @config["tests"].empty? ? "the whole suite" : "the selected specs"
        @diagnostics.inform("building coverage map (runs #{scope} once)")
        # The suite child forked next inherits this heap; pack it first, to
        # reduce later copying of shared pages.
        Execution::ForkReadiness.prepare_heap
        heartbeat = @diagnostics.progress_heartbeat("building coverage map")
        result = @supervisor.run(timeout: @config["coverage_timeout"], on_tick: heartbeat.method(:tick)) do |writer|
          record(writer, files)
        end
        map_from(result)
      end

      def map_from(result)
        raise Error, "coverage map build stopped: #{result.detail}" if result.stopped_by
        raise Error, "coverage map build failed: #{died(result.exit_status)}" if result.payload.empty?

        data = JSON.parse(result.payload)
        raise Error, "coverage map build failed: #{data['error']}" if data["error"]

        with_parent_load_lines(Selection::CoverageMap.from_json(result.payload))
      end

      # The parent's load lines merge into the freshly built map: the forked
      # build child cannot inherit the parent's Coverage counters.
      def with_parent_load_lines(map)
        @load_lines.empty? ? map : map.with_load_lines(@load_lines)
      end

      # A whole-suite build that records nothing - no line hit and no method
      # call - in any included file fails the run (exit 3): usually no test
      # in the suite exercises these files, or the setup hid the app from
      # Coverage (Bootsnap's compile cache is the default Rails case). An
      # all-endless-def file records method calls only and passes. Either way
      # a run on a truly empty map would test nothing, and exit 0 would lie.
      # With explicit tests (--test) an empty map is a legitimate outcome
      # instead: the user narrowed the suite to specs that may not touch
      # these sources, so the map passes with a warning. Applies to a cached
      # map too, so a map cached before this check cannot keep a run green,
      # and the guard runs before saving, so an empty map is never cached.
      def refuse_empty_map(map, files)
        return map if files.empty? || !map.empty?

        if @config["tests"].empty?
          raise Error, "Coverage recorded nothing in #{files.size} included files during a whole-suite " \
                       "build. No test in the suite may exercise these files, or the setup hid the app " \
                       "from Coverage (Bootsnap's compile cache is the default Rails case). " \
                       "Run `saboteur doctor`."
        end
        @diagnostics.warn("Coverage recorded nothing in #{files.size} included files; " \
                          "the selected specs may not exercise them.")
        map
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
