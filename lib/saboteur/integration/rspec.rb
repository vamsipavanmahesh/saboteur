# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "delegate"

module Saboteur
  module Integration
    # Loads spec files once in the parent. In a child, narrows the already
    # loaded world to the requested example ids and runs it with a private
    # reporter, so nothing is printed and no status file is written.
    class RSpec < Base
      def setup
        require_framework
        ::RSpec::Core::Runner.disable_autorun!
        @runner = ::RSpec::Core::Runner.new(configuration_options)
        load_output = SetupOutputCapture.new($stdout)
        begin
          @runner.setup($stderr, load_output)
        rescue SystemExit => e
          load_output.replay
          # A spec file calling exit at load makes RSpec print "While
          # loading <file> ..." (which names the file) and re-raise.
          # Uncaught, the parent exits with the spec's status: exit(0)
          # would end the run silently green (#411).
          raise Error, "a spec file called exit while loading (status #{e.status})"
        end
        configuration.order = "rand:#{config.fetch('seed', 1)}"
        if quit_while_loading?(world)
          # RSpec's load dump ends in the saboteur frames the load was
          # triggered through and a "No examples found." from the reporter;
          # both contradict the tool's own message. Print the suite's error
          # without them (#608).
          $stdout.write LoadErrorReport.filter(load_output.text, verbose: config.fetch("verbose", false))
          raise Error, load_failure_message(load_output.failed_files, load_output.text)
        end
        load_output.replay

        refuse_unintended_focus
      end

      # RSpec only adds its default path when $0 is `rspec`, so saboteur adds
      # it when RSpec's own parse of the args, .rspec and SPEC_OPTS names no
      # file or directory to run. Parsing, not a look at the tokens, keeps an
      # option value such as `--require spec_helper` from passing as a path,
      # and a --default-path from .rspec wins over "spec".
      def rspec_args
        require_framework
        args = Array(config.fetch("rspec_args", []))
        options = ::RSpec::Core::ConfigurationOptions.new(args).options
        Array(options[:files_or_directories_to_run]).empty? ? args + [options[:default_path] || "spec"] : args
      end

      # RSpec's own parser reads rspec_args and .rspec, so option values such
      # as `--require path` stay intact. Explicit tests then replace only the
      # files and directories to run.
      def configuration_options
        ::RSpec::Core::ConfigurationOptions.new(rspec_args).tap do |options|
          explicit = Array(config.fetch("tests", []))
          options.options[:files_or_directories_to_run] = explicit if explicit.any?
        end
      end

      # The spec files the configured suite runs, as UTF-8 paths relative to
      # root (a file outside it stays absolute), by
      # RSpec's own rules: .rspec, rspec_args, the default path, --pattern
      # and --exclude-pattern. RSpec applies the patterns only to the
      # directories it scans, never to a file named explicitly, so a file
      # saboteur names as a test must come from this list (#307). Nothing is
      # loaded and nothing global changes: only the file-selection options
      # reach a fresh Configuration, so --require, -I and formatters are
      # ignored. A pattern set in Ruby (RSpec.configure in a spec helper) is
      # not seen. RSpec resolves patterns against the working directory, so
      # this reads from the root.
      def configured_spec_files(root)
        require_framework
        from_directory(root) do
          options = ::RSpec::Core::ConfigurationOptions.new(rspec_args).options
          configuration = ::RSpec::Core::Configuration.new
          %i[default_path pattern exclude_pattern].each do |name|
            configuration.public_send(:"#{name}=", options[name]) if options[name]
          end
          configuration.files_or_directories_to_run = options[:files_or_directories_to_run]
          # RSpec expands from the working directory, which can spell the
          # root differently from its realpath (/var and /private/var).
          prefix = Text.utf8_identity(File.join(Dir.pwd, ""))
          configuration.files_to_run.map { |file| Text.utf8_identity(file).delete_prefix(prefix) }
        end
      end

      # A missing rspec-core is the target's setup error, not a saboteur
      # defect (#482): refuse with the remedy instead of crashing into the
      # internal-error report. It is a usage error (#610): ConfigError maps
      # to exit 2, and the remedy names docs/minitest.md rather than
      # c.integration - rspec is the only integration, so pointing at it
      # sent Minitest users down a dead end. Only the framework's own LoadError converts -
      # matched on the failed feature, not the message, so a missing
      # rspec/core_ext does not pose as rspec/core; a LoadError the app's
      # files raise keeps the crash route.
      def require_framework
        require "rspec/core"
      rescue LoadError => e
        raise unless e.path == "rspec/core"

        raise ConfigError, "rspec is not in the bundle: the RSpec integration needs the rspec-core gem. " \
                           "Add it to the bundle's test group. saboteur's built-in integration supports RSpec only - " \
                           "see docs/minitest.md for other suites"
      end

      def all_tests
        groups = world.ordered_example_groups.flat_map(&:descendants)
        groups.flat_map { |group| world.filtered_examples[group] }
              .map { |example| TestCase.new(id: example.id, file: example.metadata[:rerun_file_path]) }
      end

      # Whether RSpec picks examples from its generated status file
      # (spec/examples.txt) for --only-failures or --next-failure. RSpec's own
      # parser answers, so abbreviations, SPEC_OPTS, .rspec, .rspec-local,
      # ~/.rspec, the XDG options file and --options FILE all count.
      def status_file?(root)
        from_directory(root) { ::RSpec::Core::ConfigurationOptions.new(rspec_args).options[:only_failures] ? true : false }
      end

      def test_files
        world.example_groups.map { |group| File.expand_path(group.metadata[:file_path]) }.uniq
      end

      # Loads spec files the run's own selection left out, in the parent, so a
      # forked confirmation run can execute their examples (#1286). Files
      # already loaded are skipped; a file that defines no group is an error,
      # since its examples could never run.
      def load_spec_files(paths)
        loaded = test_files
        absolute = paths.map { |path| File.expand_path(path, config.root) }.uniq
        (absolute - loaded).each do |path|
          require_inside_root(path)
          before = world.example_groups.size
          from_directory(config.root) { load(path) }
          raise RefusedSpecPath, "#{path} defines no example group" if world.example_groups.size == before
        end
      end

      # The ids come from a cached coverage map, which is untrusted input
      # (#427): only a spec file that really lives under the project root,
      # symlinks resolved, may be loaded.
      def require_inside_root(path)
        raise RefusedSpecPath, "refusing to load #{path}: not a *_spec.rb file" unless path.end_with?("_spec.rb")

        root = File.realpath(config.root)
        real = File.realpath(path)
        return if real.start_with?("#{root}#{File::SEPARATOR}") && real.end_with?("_spec.rb")

        raise RefusedSpecPath, "refusing to load #{path}: it resolves outside the project root"
      rescue SystemCallError
        raise RefusedSpecPath, "refusing to load #{path}: it does not exist under the project root"
      end

      # Runs the tests in the order given: groups by their earliest example,
      # examples by position.
      def run(ids)
        wanted = Set.new(ids)
        narrow_to(wanted)
        order_by(ids)
        configuration.fail_fast = config["matrix"] ? false : 1
        listener = Listener.new
        passed = execute(listener)
        RunResult.new(passed: passed && listener.failed.empty?, failed_ids: listener.failed,
                      executed_ids: listener.executed, runtime: listener.runtime,
                      failure_classes: listener.failure_classes, failure_messages: listener.failure_messages,
                      failure_details: listener.failure_details)
      end

      def example_count(files: nil)
        world.example_count(runnable_groups(files))
      end

      def run_all(recorder, files: nil, seed: nil)
        configuration.order = "rand:#{seed || config.fetch('seed', 1)}"
        configuration.fail_fast = false
        execute(Listener.new(recorder), log_phase: true, files: files)
      end

      def run_baseline(seed:, files: nil)
        configuration.order = "rand:#{seed}"
        configuration.fail_fast = false
        listener = Listener.new
        passed = execute(listener, log_phase: true, files: files)
        RunResult.new(passed: passed && listener.failed.empty?, failed_ids: listener.failed,
                      executed_ids: listener.executed, runtime: listener.runtime,
                      failure_classes: listener.failure_classes, failure_messages: listener.failure_messages,
                      failure_details: listener.failure_details)
      end

      SHOWN_LOAD_FAILURES = 5

      # Ruby's Coverage refuses a second start, so a suite whose
      # spec_helper auto-starts SimpleCov/SingleCov collides with
      # saboteur's own Coverage.start and the load quits with an opaque
      # "No examples found" (#645, real run: audited @ dbf84326). Name the
      # suspect and both guard styles. The gem's backtrace line is the
      # fallback: the RuntimeError's text is Coverage's own, whoever
      # started it second.
      COVERAGE_DOUBLE_START = /coverage measurement is already setup/i
      # A gem backtrace frame (path:line) or the start call itself - never a
      # bare name, which a spec FILE name like simplecov_config_spec.rb
      # would false-positive on (Pod 3 QA probe, #645).
      COVERAGE_GEM_FRAME = %r{(?:single_cov|simplecov)[\w.\-/]*\.rb:\d+|\b(?:SimpleCov\.start|SingleCov\.setup)}i

      private

      # rspec-core 3.11 added rspec_is_quitting (SyntaxError and SystemExit
      # at load quit through it, not through wants_to_quit). The gemspec
      # does not pin rspec, so a target app can carry an older rspec-core;
      # ask before reading the newer flag (#378).
      def quit_while_loading?(world)
        world.wants_to_quit || (world.respond_to?(:rspec_is_quitting) && world.rspec_is_quitting)
      end

      # The quit reason RSpec keeps is only a flag; the failing files it
      # printed are what a user needs. Name them and the way out: a repo
      # whose spec tree cannot load whole (an engine's dummy app, an
      # env-dependent integration spec) must narrow what loads (#378).
      def load_failure_message(failed_files, captured_text = nil)
        message = +"rspec quit while loading spec files"
        if failed_files.any?
          shown = failed_files.first(SHOWN_LOAD_FAILURES)
          rest = failed_files.size - shown.size
          message << ": #{failed_files.size} failed to load:"
          shown.each { |file| message << "\n  #{file}" }
          message << "\n  ... and #{rest} more" if rest.positive?
        end
        message << "\nExclude the broken subtrees in config/saboteur.rb, e.g. " \
                   'c.rspec_args = ["--exclude-pattern", "spec/dummy/**/*_spec.rb"], or name the ' \
                   "suite with --test. Rails engines with an embedded dummy app (spec/dummy) need " \
                   'this; see README "Rails engines and dummy apps".'
        hints = EnvironmentHints.all(config.root)
        message << "\nSuspect: #{hints.join('; ')}." if hints.any?
        if coverage_suspect?(captured_text)
          message << "\nSuspect: your suite starts its own Coverage (saboteur starts one itself). " \
                     "Guard it - if ENV[\"COVERAGE\"], or SingleCov's conditional setup API - " \
                     "and see docs/recipes/README.md#simplecov."
        end
        message
      end

      def coverage_suspect?(captured_text)
        captured_text&.match?(COVERAGE_DOUBLE_START) || captured_text&.match?(COVERAGE_GEM_FRAME) || false
      end

      def refuse_unintended_focus
        return if config["allow_focus"]

        FocusGuard.new(world:, explicit_filter_keys: explicit_inclusion_keys).check!
      end

      # Inclusion filters the user named in rspec_args or .rspec, such as
      # `--tag slow`. Those narrow the run on purpose.
      def explicit_inclusion_keys
        options = configuration_options
        filter_manager = ::RSpec::Core::FilterManager.new
        options.configure_filter_manager(filter_manager)
        keys = filter_manager.inclusions.rules.keys
        # `--example TEXT` becomes a :full_description rule when the options
        # reach the configuration, not in the filter manager.
        options.options[:full_description] ? keys + [:full_description] : keys
      end

      # A real run already starts in the root; only a caller elsewhere (a
      # spec) changes directory, and only for the block.
      def from_directory(root, &)
        File.realpath(Dir.pwd) == File.realpath(root) ? yield : Dir.chdir(root, &)
      end

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

      # log_phase is for the baseline and coverage children, whose $stdout is
      # redirected to the phase's log: progress and failure detail land in
      # that log, so a failed phase can be diagnosed from it. Mutant runs
      # stay quiet.
      def execute(listener, log_phase: false, files: nil)
        reporter = ::RSpec::Core::Reporter.new(configuration)
        reporter.register_listener(listener, *Listener::EVENTS)
        groups = runnable_groups(files)
        count = world.example_count(groups)
        if log_phase
          logger = PhaseLogger.new($stdout, total: count)
          reporter.register_listener(logger, *PhaseLogger::EVENTS)
        end
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        passed = reporter.report(count) do |r|
          configuration.with_suite_hooks { groups.map { |group| group.run(r) }.all? }
        end
        listener.runtime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        passed && !world.non_example_failure
      end

      # The top-level groups with examples to run, in the world's order. With
      # files, only the groups a spec file in that list defines (a part of a
      # partitioned coverage build, #741). Both sides are compared as real
      # paths. An empty list is refused and so is a listed file that defines
      # no group: a part that silently runs nothing would leave its tests
      # out of the map.
      def runnable_groups(files)
        groups = world.ordered_example_groups.select { |group| group.descendant_filtered_examples.any? }
        return groups unless files
        raise ArgumentError, "files must name at least one spec file" if files.empty?

        wanted = files.to_set { |file| File.realpath(file) }
        chosen = groups.select { |group| wanted.include?(real_path(group.metadata[:file_path])) }
        missing = wanted - chosen.to_set { |group| real_path(group.metadata[:file_path]) }
        raise ArgumentError, "no example group in: #{missing.sort.join(', ')}" unless missing.empty?

        chosen
      end

      def real_path(path)
        File.realpath(path)
      rescue SystemCallError
        File.expand_path(path)
      end

      # Progress and failure detail for a phase log. Every 25 finished
      # examples is enough to see movement on a tail; failures print RSpec's
      # full formatted detail, and the run ends with RSpec's totals line.
      class PhaseLogger
        EVENTS = %i[example_finished message dump_failures dump_summary].freeze

        PROGRESS_EVERY = 25

        def initialize(out, total:)
          @out = out
          @total = total
          @executed = 0
        end

        def example_finished(_notification)
          @executed += 1
          return unless @executed == @total || (@executed % PROGRESS_EVERY).zero?

          @out.puts("#{@executed}/#{@total} examples finished")
        end

        # A failure outside any example (a suite hook, a load error) arrives
        # as a message, never in dump_failures.
        def message(notification)
          @out.puts(notification.message)
        end

        def dump_failures(notification)
          @out.puts(notification.fully_formatted_failed_examples)
        end

        def dump_summary(notification)
          @out.puts(notification.totals_line)
        end
      end

      # RSpec prints each load failure ("An error occurred while loading
      # ...") to the output stream during setup and only marks
      # world.wants_to_quit. Capture the stream while passing everything
      # through, so the tool error can name the files (#378).
      class SetupOutputCapture < SimpleDelegator
        LOAD_FAILURE = [
          /^An error occurred while loading (\S+?)\.?(?: - Did you mean\?)?$/,
          # SyntaxError and SystemExit use their own wording (#378).
          /^While loading (\S+?) an? `(?:raise SyntaxError|exit)`/
        ].freeze

        def initialize(io)
          super
          @captured = +""
        end

        # Buffer only: the caller decides after setup whether the captured
        # text goes out as it is (a clean load), filtered (a load quit,
        # #608) or verbatim on a SystemExit. Passing through during setup
        # would print what a later filter needs to drop.
        def write(text)
          @replayed ? __getobj__.write(text) : @captured << text
          self
        end

        def print(*args)
          write(args.join)
        end

        def puts(*args)
          write("#{args.flatten.join("\n")}\n")
        end

        def replay
          __getobj__.write(@captured)
          # RSpec retains this stream for later suite-hook errors.
          @replayed = true
        end

        def text = @captured

        def failed_files
          LOAD_FAILURE.flat_map { |pattern| @captured.scan(pattern) }.flatten
        end
      end

      # The load dump RSpec prints when a spec file raises at load, trimmed
      # to what the user acts on: the first error with the suite's own
      # frames. The saboteur frames the load was triggered through and the
      # reporter's "No examples found." (nothing ran because nothing loaded)
      # read as saboteur crashing and contradict the tool's message; both
      # stay under --verbose (#608).
      class LoadErrorReport
        HEADER = /^An error occurred while loading /
        # The running tool's install root (a checkout or an unpacked gem),
        # with separator. Only frames under it are saboteur's: the same
        # lib/saboteur/ layout under ANOTHER root is the target's vendored
        # copy or a dogfooded checkout, and those frames are the suite's
        # (#608).
        TOOL_ROOT = "#{File.expand_path('../../..', __dir__)}/".freeze
        private_constant :HEADER, :TOOL_ROOT

        def self.filter(text, verbose: false)
          return text if verbose

          lines = text.lines.reject { |line| line.strip == "No examples found." || saboteur_frame?(line) }
          heads = lines.each_index.select { |index| lines[index].match?(HEADER) }
          return lines.join if heads.size <= 1

          kept = lines[0...heads[1]]
          kept.pop while kept.last&.strip == ""
          omitted = heads.size - 1
          kept << "(#{omitted} more load error#{'s' if omitted > 1} omitted; rerun with --verbose for the full list)\n"
          kept.join
        end

        # A backtrace frame inside the tool's install root. Relative frames
        # (the suite's own "./spec/...") are never the tool's.
        def self.saboteur_frame?(line)
          line = line.strip
          return false unless line.start_with?("# ")

          path = line.sub(/\A#\s+/, "").sub(/:\d+:in .*\z/, "")
          path.start_with?("/") && File.expand_path(path).start_with?(TOOL_ROOT)
        end
        private_class_method :saboteur_frame?
      end

      class Listener
        EVENTS = %i[example_started example_finished example_failed].freeze

        MESSAGE_LIMIT = 200
        DETAIL_LIMIT = 2_000
        BACKTRACE_LIMIT = 5

        attr_reader :executed, :failed, :failure_classes, :failure_messages, :failure_details
        attr_accessor :runtime

        def initialize(recorder = nil)
          @recorder = recorder
          @executed = []
          @failed = []
          @failure_classes = {}
          @failure_messages = {}
          @failure_details = {}
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
          @failure_details[notification.example.id] = detail_for(exception)
        end

        private

        # The full failure, class and first frames: a neutral re-run that
        # fails needs enough context to explain why (the compact first line
        # alone reads as just "expected: 0").
        def detail_for(exception)
          return nil unless exception

          message = Text.utf8("#{exception.class.name}: #{exception.message}")
          ([message] + relevant_frames(exception)).join("\n")[0, DETAIL_LIMIT]
        rescue StandardError
          exception.message.to_s.dump[0, DETAIL_LIMIT]
        end

        # An expectation failure leads with rspec's own frames (notify_failure,
        # handle_failure); under the cap they would crowd out the spec line.
        # Keep the project frames; fall back to the raw ones when rspec itself
        # raised, so the detail never comes back empty.
        def relevant_frames(exception)
          frames = Array(exception.backtrace).map { |frame| Text.utf8(frame.to_s) }
          project = frames.reject { |frame| frame.include?("/gems/rspec") }
          (project.empty? ? frames : project).first(BACKTRACE_LIMIT)
        end

        def first_line(message)
          # Exception messages can carry bytes invalid under the locale encoding
          # (e.g. a path with raw bytes); scrub before splitting, or .lines/.strip
          # raises Encoding::CompatibilityError and the run reports error (CI #272).
          Text.utf8(message.to_s).lines.map(&:strip).find { |line| !line.empty? }.to_s[0, MESSAGE_LIMIT]
        rescue StandardError
          # Text.utf8 is mutable code: when the mutant under test breaks it,
          # the raise must not flip the run to error - the recorded failure
          # is what classifies the kill. dump is ASCII-safe for any bytes.
          message.to_s.dump[0, MESSAGE_LIMIT]
        end
      end
    end

    register :rspec, RSpec
  end
end
