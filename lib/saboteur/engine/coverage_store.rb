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
      include CoverageShadow
      include CoveragePartial
      include CoverageParts

      CACHE_INPUTS = %w[integration require rspec_args rails tests coverage_recorder].freeze
      # Names the freshest whole-suite map build; read as an untrusted hint:
      # only a bare 64-hex key joins the cache dir (#427).
      WHOLE_SUITE_POINTER = "whole-suite-map"
      LOCKFILES = %w[Gemfile.lock gems.locked].freeze
      LOG = "coverage-build.log"
      # RSpec rewrites this on every run (example_status_persistence_file_path),
      # so hashing it would make every second run look edited.
      GENERATED_OUTPUT = "spec/examples.txt"
      # A snapshot entry that is never a file, so a snapshot holding it is never
      # reused partially. It stands for a test file outside the project root,
      # whose own inputs the snapshot cannot see.
      OUTSIDE_TESTS = "(test file outside the project root)"
      # What a failed child's log shows in the error: its last lines, bounded.
      TAIL_LINES = 60
      TAIL_BYTES = 65_536
      TAIL_LINE_WIDTH = 300

      def initialize(config:, integration:, hooks:, supervisor:, diagnostics:, load_lines: {}, load_methods: {},
                     timeout_cap: nil, parts: 1, whole_suite_run: false)
        @config = config
        @parts = parts
        @integration = integration
        @hooks = hooks
        @supervisor = supervisor
        @diagnostics = diagnostics
        @timeout_cap = timeout_cap
        @load_lines = load_lines
        @load_methods = load_methods
        @whole_suite_run = whole_suite_run
        @root = File.realpath(config.root)
        @root_prefixes = Selection::CoverageMap.root_prefixes(config.root)
      end

      # True when fetch would reuse the cached map instead of running the
      # suite pass that builds it: lets the run announce the real number of
      # full passes up front (#260). Loads the map with the same validation
      # fetch uses and retains it, so a corrupt or truncated cache announces
      # a build pass, not a reuse it cannot keep.
      def reusable?(files)
        !cached_map(files).nil?
      end

      def fetch(files)
        path = cache_path(files)
        preloaded = LoadCoverage.preloaded_uninstrumented(files)
        cached = cached_map(files)
        return serve_cached(path, cached, files, preloaded) if cached

        note = miss_note(files)
        @diagnostics.inform(note.message(scoped: !@config["tests"].empty?)) if @config["cache"]
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        map = fresh_map(files, note, preloaded)
        build_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        persist_map(path, map)
        shadow(files, map, note, build_seconds) if shadow?
        note.save
        File.write(File.join(@config.path("cache_dir"), "preview.json"),
                   JSON.generate(path: path, fingerprint: RunFingerprint.new(config: @config).snapshot.digest))
        map
      end

      # The map a whole-suite coverage build wrote on this tree, or nil.
      # Survivor presentation consults it (presentation only, never
      # selection): in a scoped run the run's own map holds only the specs
      # the run loaded, so a "covered by" list from it can read as complete
      # when another spec pins the behavior (false survivors by default,
      # review C1). A full run keys its map with tests: [], so the lookup
      # overrides a scoped run's --test value.
      # The map this store's fetch produced (or served from cache): the
      # run's own selection map, read by survivor presentation (review C1).
      attr_reader :fetched_map

      def whole_suite_map
        return nil unless @config["cache"]

        pointer = File.join(@config.path("cache_dir"), WHOLE_SUITE_POINTER)
        return nil unless File.file?(pointer)

        key = File.read(pointer, encoding: Encoding::UTF_8).strip
        return nil unless key.match?(/\A[0-9a-f]{64}\z/)

        Selection::CoverageMap.load(File.join(@config.path("cache_dir"), "coverage-#{key}.json"))
      rescue SystemCallError, EncodingError
        nil
      end

      private

      # The partial map when it is on and safe, else the full build.
      def fresh_map(files, note, preloaded)
        (partial_map(files, note, preloaded) if partial_use?) ||
          refuse_empty_map(build(files).with_preloaded(preloaded), files, preloaded)
      end

      def write_map(writer, recorder, build_seconds)
        writer.write(recorder.result(build_seconds: build_seconds, loaded_files: loaded_project_files).to_json)
        writer.close
      end

      # Every project source this child loaded, even a lazy require outside the
      # include list that the recorder drops: --incremental must watch it, or a
      # change there keeps stale verdicts (#353).
      def loaded_project_files
        $LOADED_FEATURES.filter_map do |file|
          path = Text.utf8_strict(Selection::CoverageMap.canonical(file))
          path if path.end_with?(".rb") && @root_prefixes.any? { |prefix| path.start_with?(prefix) }
        end
      end

      def cache_path(files)
        File.join(@config.path("cache_dir"), "coverage-#{cache_key(files)}.json")
      end

      def cached_map(files)
        return nil unless @config["cache"]

        @cached_map ||= Selection::CoverageMap.load(cache_path(files))
      end

      def serve_cached(path, cached, files, preloaded)
        record_whole_suite_map(path)
        refuse_empty_map(@fetched_map = cached.with_preloaded(preloaded), files, preloaded)
      end

      def persist_map(path, map)
        map.save(path)
        record_whole_suite_map(path)
        @fetched_map = map
      end

      # The engine tells us when this run is a whole-suite build (no
      # --since, no subjects, no explicit --test): remember the map key for
      # later scoped runs, whose tree has usually drifted past the exact
      # cache key already (review C1).
      def record_whole_suite_map(path)
        return unless @whole_suite_run

        File.write(File.join(@config.path("cache_dir"), WHOLE_SUITE_POINTER),
                   File.basename(path, ".json").delete_prefix("coverage-"), perm: 0o600)
      end

      def cache_key(files)
        Selection::CoverageMap.cache_key(files: key_files(files), extra: key_inputs)
      end

      def key_inputs
        JSON.generate(CACHE_INPUTS.to_h { |key| [key, @config[key]] })
      end

      def recorder_class
        @config["coverage_recorder"] == "trace" ? Selection::TraceRecorder : Selection::Recorder
      end

      def key_files(files)
        (files + @integration.test_files + SuiteFiles.new(@config).files + lockfiles).uniq
      end

      def miss_note(files)
        CoverageMissNote.new(cache_dir: @config.path("cache_dir"), root: @root, files: snapshot_files(files),
                             settings: key_inputs, map_key: cache_key(files), seed: @config["seed"],
                             clean: ->(path) { plain_line(Text.utf8(path.to_s)) })
      end

      # What the inputs snapshot hashes: the cache key's files plus every file
      # under spec/ and under the suite's own test directories, fixtures and
      # config included, except the generated spec/examples.txt. A partial
      # rebuild (#46) must see a change to anything a test can read, not only
      # to what the key covers. Symlinks and other special entries are listed
      # but never read (see CoverageInputsSnapshot.file_digest). The cache dir
      # is left out so the pair never hashes itself.
      def snapshot_files(files)
        cache = File.join(File.expand_path(@config.path("cache_dir")), "")
        dirs, outside = test_dirs
        tree = dirs.flat_map do |dir|
          Dir.glob("**/*", File::FNM_DOTMATCH, base: File.join(@root, dir)).map { |name| File.join(@root, dir, name) }
        end
        generated = File.join(@root, GENERATED_OUTPUT)
        tree = tree.reject do |file|
          file == generated || real_directory?(file) || File.expand_path(file).start_with?(cache)
        end
        marker = outside ? [OUTSIDE_TESTS] : []
        [key_files(files), tree, marker].flatten.sort
      end

      # spec/ always, plus the first directory of every configured test file
      # (a suite under test/ or elsewhere keeps its fixtures beside it), and
      # whether a test file lies outside the project root. Both sides are
      # compared as real paths, so a symlinked root still matches.
      def test_dirs
        prefix = "#{Selection::CoverageMap.canonical(@root)}/"
        inside, outside = @integration.test_files.map { |file| Selection::CoverageMap.canonical(file) }
                                      .partition { |file| file.start_with?(prefix) }
        [["spec"] + inside.map { |file| file.delete_prefix(prefix).split("/").first }, !outside.empty?]
      end

      def real_directory?(file)
        File.lstat(file).directory?
      rescue SystemCallError
        true
      end

      def lockfiles
        LOCKFILES.map { |file| File.join(@root, file) }.select { |file| File.file?(file) }
      end

      # An admitted build still gets only the time left in the run budget
      # (see BaselineGuard#phase_timeout).
      def build_timeout
        @timeout_cap ? @timeout_cap.call(@config["coverage_timeout"]) : @config["coverage_timeout"]
      end

      def build(files)
        unless Coverage.respond_to?(:state) && Coverage.state == :suspended
          raise Error, "Coverage is #{Coverage.state}; saboteur must set it up before the app loads. " \
                       "Run through the saboteur executable and disable SimpleCov for the run."
        end

        parts = usage_checked { suite_parts }
        return build_parts(files, parts) if parts.size > 1

        scope = @config["tests"].empty? ? "the whole suite" : "the selected specs"
        @diagnostics.inform("building coverage map (runs #{scope} once)")
        # The suite child forked next inherits this heap; pack it first, to
        # reduce later copying of shared pages.
        Execution::ForkReadiness.prepare_heap
        heartbeat = @diagnostics.progress_heartbeat("building coverage map").watch(log_path)
        admitted = build_timeout
        result = @supervisor.run(timeout: admitted, on_tick: heartbeat.method(:tick),
                                 label: "coverage child died during the map build") do |writer|
          record(writer, files)
        end
        map_from(result, admitted)
      end

      # The spec files dealt into @parts disjoint parts; one part (the
      # default, or a suite with fewer files than parts) keeps the single
      # child build (#741).
      def suite_parts
        return [] unless @parts > 1

        Engine::SuitePartition.parts(@integration.test_files, @parts)
      end

      # The same suite pass as build, run as several children at once, each
      # over its own spec files. Fails loudly unless the parts hold exactly
      # the suite's examples before the run and the combined map holds
      # exactly its tests after it, and refuses a part that recorded no test.
      def build_parts(files, parts)
        total, counts = usage_checked { check_parts_cover_suite(parts) }
        saved = saved_parts(files, parts.size, counts)
        todo = saved.each_index.select { |index| saved[index].nil? }
        @diagnostics.inform(parts_note(parts.size, todo.size))
        built = todo.empty? ? [] : run_parts(files, parts, todo)
        todo.zip(built) { |index, map| saved[index] = map }
        map = combine_saved(saved, total, files, parts.size)
        forget_parts(files, parts.size)
        map
      end

      # Parts that cannot be combined are dropped, not kept: a bad saved
      # part would otherwise fail every later run the same way.
      def combine_saved(maps, total, files, count)
        combine_parts(maps, total)
      rescue ArgumentError => e
        forget_parts(files, count)
        raise Error, "the saved coverage parts do not combine (#{e.message}); they were removed, run again"
      end

      def parts_note(count, missing)
        return "building coverage map (reusing all #{count} saved parts)" if missing.zero?

        reused = count - missing
        suffix = reused.zero? ? "" : ", reusing #{reused} saved"
        "building coverage map (runs the suite once, in #{count} parallel parts#{suffix})"
      end

      # Runs only the parts in todo, as several children at once.
      def run_parts(files, parts, todo)
        Execution::ForkReadiness.prepare_heap
        heartbeat = @diagnostics.progress_heartbeat("building coverage map")
        admitted = build_timeout
        results = @supervisor.run_many(todo.size, timeout: admitted, on_tick: heartbeat.method(:tick),
                                                  label: "coverage child died during the map build") do |writer, slot|
          index = todo[slot]
          own_test_env(index)
          record(writer, files, only: parts[index], log: part_log_path(index))
        end
        part_maps(results, admitted, parts.size, files, todo)
      end

      # Every part that failed is reported, each with its own output, so one
      # run shows all the failures instead of the first. A budget stop still
      # raises at once: it says nothing about the suite. A part that did
      # finish is saved either way, so the work is not lost (#427).
      def part_maps(results, admitted, count, files, todo)
        failures = []
        budget_stop = nil
        maps = results.each_with_index.map do |result, slot|
          index = todo[slot]
          map_from(result, admitted, log: part_log_path(index)).tap { |map| save_part(map, files, index, count) }
        rescue BudgetPhaseTimeout => e
          budget_stop = e
          nil
        rescue Error => e
          failures << "part #{index + 1} of #{count}: #{e.message}"
          nil
        end
        raise budget_stop if budget_stop
        raise Error, failures.join("\n") unless failures.empty?

        maps.each_with_index { |map, slot| part_map(map, todo[slot], count) }
      end

      # A part child gets its own TEST_ENV_NUMBER, as a WorkerPool worker
      # does, so suites that key databases, ports or tmp dirs on it do not
      # collide between parts (part 0 keeps the empty value).
      def own_test_env(index)
        ENV["TEST_ENV_NUMBER"] = index.zero? ? "" : (index + 1).to_s
      end

      # A bad file list is the caller's mistake: a usage error, not a crash.
      def usage_checked
        yield
      rescue ArgumentError => e
        raise ConfigError, e.message
      end

      def check_parts_cover_suite(parts)
        total = @integration.example_count
        counts = parts.map { |part| @integration.example_count(files: part) }
        return [total, counts] if counts.sum == total

        raise Error, "the coverage parts hold #{counts.sum} examples but the suite has #{total}; " \
                     "refusing to build a map from a partition that does not cover the suite"
      end

      def part_map(map, index, total)
        return map unless map.tests.empty?

        raise Error, "coverage part #{index + 1} of #{total} recorded no tests; refusing to build a partial map"
      end

      def combine_parts(maps, total)
        map = Selection::CoverageMap.combine(maps)
        return map if map.tests.size == total

        raise Error, "the combined coverage map holds #{map.tests.size} tests but the suite has #{total}; " \
                     "refusing to use a partial map"
      end

      def part_log_path(index)
        File.join(@config.path("cache_dir"), "coverage-build-#{index + 1}.log")
      end

      def map_from(result, admitted = @config["coverage_timeout"], log: log_path)
        raise_budget_stop(admitted) if budget_stopped?(result, admitted)
        raise Error, "coverage map build stopped: #{result.detail}" if result.stopped_by
        if result.payload.empty?
          raise Error,
                "coverage map build failed: #{died(result.exit_status, log)}#{output_tail(log)}"
        end

        data = JSON.parse(result.payload)
        raise Error, "coverage map build failed: #{child_error(data['error'])}#{output_tail(log)}" if data["error"]

        with_parent_load_lines(Selection::CoverageMap.from_json(result.payload))
      end

      # A build that hit its deadline only because --max-duration shortened
      # the admission below the configured phase timeout: the budget ended
      # the run, the suite is not broken (see BaselineGuard#budget_stopped?).
      def budget_stopped?(result, admitted)
        result.stopped_by == :timeout && admitted < @config["coverage_timeout"]
      end

      def raise_budget_stop(admitted)
        raise BudgetPhaseTimeout, "the --max-duration budget stopped the coverage map build " \
                                  "(admitted #{admitted.round(1)}s of the #{@config['coverage_timeout']}s " \
                                  "phase timeout)"
      end

      # The parent's load lines merge into the freshly built map: the forked
      # build child cannot inherit the parent's Coverage counters.
      def with_parent_load_lines(map)
        @load_lines.empty? && @load_methods.empty? ? map : map.with_load_lines(@load_lines, @load_methods)
      end

      # A whole-suite build that records nothing - no line hit and no method
      # call - in any included file fails the run (exit 3). The recorder's map
      # also holds the suite's spec files, so the check is per included file,
      # not whole-map: a suite that tests nothing here still records its own
      # spec code. Usually no test in the suite exercises these files, or
      # the setup hid the app from Coverage (Bootsnap's compile cache is the
      # default Rails case). An
      # all-endless-def file records method calls only and passes. Either way
      # a run on a truly empty map would test nothing, and exit 0 would lie.
      # With explicit tests (--test) an empty map is a legitimate outcome
      # instead: the user narrowed the suite to specs that may not touch
      # these sources, so the map passes with a warning. Applies to a cached
      # map too, so a map cached before this check cannot keep a run green,
      # and the guard runs before saving, so an empty map is never cached.
      def refuse_empty_map(map, files, preloaded)
        return map if files.empty? || !map.empty_for?(files)

        # A file loaded before the executable's Coverage.start can never be
        # instrumented, so emptiness there is a setup defect, not untested
        # code: name it apart from the generic no-coverage refusal.
        preloaded_empty = preloaded & files.map { |file| Selection::CoverageMap.canonical(file) }
        if preloaded_empty.any?
          message = preloaded_message(preloaded_empty)
          raise Error, message if @config["tests"].empty?

          @diagnostics.warn(message)
          return map
        end
        if @config["tests"].empty?
          raise Error, "Coverage recorded nothing in #{files.size} included files during a whole-suite " \
                       "build. No test in the suite may exercise these files, or the setup hid the app " \
                       "from Coverage#{bootsnap_note}. Run `saboteur doctor`."
        end
        @diagnostics.warn("name the specs that exercise them in --test, or drop --test to run the whole suite\n  " \
                          "Coverage recorded nothing in #{files.size} included files; " \
                          "the selected specs may not exercise them.")
        map
      end

      def preloaded_message(files)
        names = Text.name_list(files.map { |file| file.delete_prefix("#{@root}/") })
        "#{names} can never be covered: loaded before saboteur started coverage\n  " \
          "a require ran before the executable's Coverage.start, commonly the gemspec requiring the " \
          "library while bundler/setup evaluates it, or RUBYOPT -r\n  " \
          "Let the test suite load these files; a gemspec should require only its version file."
      end

      # Bootsnap is named only when it is loaded: blaming a library the app
      # does not use sends the reader to the wrong place.
      def bootsnap_note
        " (Bootsnap's compile cache is the default Rails case)" if defined?(::Bootsnap)
      end

      def died(status, log)
        how = if status&.signaled? then "was killed by signal #{Signal.signame(status.termsig)}"
              else "exited with status #{status&.exitstatus}"
              end
        "the suite #{how} before reporting; its output is in #{log.delete_prefix("#{@root}/")}"
      end

      # The end of a failed child's log, where rspec prints its failures, so a
      # CI run shows why without the cache directory. The suite's own output
      # and nothing else. Every line is cleaned by plain_line and starts with
      # "| ", so it is never the start of a workflow command.
      def output_tail(log)
        size = File.size(log)
        cut = size > TAIL_BYTES
        text = File.open(log) do |file|
          file.seek(size - TAIL_BYTES) if cut
          file.read
        end
        lines = Text.utf8(text).lines
        lines.shift if cut
        lines = lines.last(TAIL_LINES).map { |line| tail_line(line) }
        return "" if lines.empty?

        "\n  the last #{lines.size} lines of #{log.delete_prefix("#{@root}/")}:\n#{lines.join("\n")}"
      rescue SystemCallError
        ""
      end

      def tail_line(line)
        "| #{plain_line(line)}"
      end

      # One line of a child's text, safe to print: colors stripped, control
      # characters escaped, cut to a readable width, and the two things
      # GitHub Actions reads as a workflow command broken where they stand: a
      # "::" that starts the line after any leading whitespace (the runner
      # trims all Unicode spaces first) and a "##[" anywhere in it. Other
      # colons and brackets, as in "Saboteur::Error", are left alone.
      def plain_line(line)
        text = Text.display_safe(line.chomp.gsub(/\e\[[0-9;]*[A-Za-z]/, ""))
        text.size > TAIL_LINE_WIDTH ? "#{text[0, TAIL_LINE_WIDTH]}..." : text
      end

      # The error a child wrote into its report. It is the child's text, which
      # can carry anything the suite printed or raised, so it gets the log's
      # treatment: the first line follows the message, every later line starts
      # with "| ", and plain_line has cleaned them all.
      def child_error(error)
        first, *rest = Text.utf8(error.to_s).lines
        [plain_line(first.to_s), *rest.first(TAIL_LINES).map { |line| tail_line(line) }].join("\n")
      end

      def log_path
        File.join(@config.path("cache_dir"), LOG)
      end

      # Runs in the supervised child. The suite's output goes to a log, so a
      # child that dies without reporting can still be diagnosed.
      def record(writer, files, only: nil, log: log_path, seed: @config["seed"])
        FileUtils.mkdir_p(File.dirname(log))
        $stdout.reopen(log, "w")
        $stdout.sync = true
        $stderr.reopen($stdout)
        @hooks.run(:after_fork)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        # The suite's own files are recorded too: a spec can read a
        # constant directly, and without its line hits no test maps to the
        # read (#319).
        recorder = recorder_class.new(files + @integration.test_files)
        recorder.start
        Kernel.srand(seed)
        passed = only ? @integration.run_all(recorder, files: only, seed: seed) : @integration.run_all(recorder)
        if passed == false
          raise Error, "the unchanged suite failed while building coverage. Fix the suite, then run again " \
                       "with seed #{seed}."
        end
        write_map(writer, recorder, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      rescue Exception => e # rubocop:disable Lint/RescueException
        writer.write(JSON.generate(error: "#{e.class}: #{e.message}"))
        exit!(1)
      end
    end
  end
end
