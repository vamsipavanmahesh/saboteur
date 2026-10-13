# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "securerandom"

module Preflight
  # Orchestrates the checks. Cheap checks all run and collect errors; the costly ones
  # (RuboCop, specs) are skipped with a recorded reason when a cheap check did not pass.
  class Runner
    attr_reader :output_directory

    def initialize(options:, directory:, command_runner: nil, run_id: nil)
      @options = options
      @directory = directory
      @run_id = run_id || "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{SecureRandom.hex(4)}"
      @output_directory = File.join(File.expand_path(OUTPUT_ROOT, directory), @run_id)
      @own_commands = command_runner.nil?
      @commands = command_runner || CommandRunner.new(directory: directory)
      @repository = Repository.new(command_runner: @commands, options: options, directory: directory)
      @inputs = ExecutionInputs.new(repository: @repository, directory: directory, command_runner: @commands)
    end

    # Order matters. Identity and the protected-path checks only read files and run git. Bundler, which evaluates
    # the candidate's Gemfile, runs only after those passed. Nothing is written until the output root is verified.
    def call
      @repository.verify_identity!
      prepare_output_directory
      first = capture_inputs { @inputs.snapshot }
      return finish([execution_gap_result("execution_inputs", first)], nil, nil) unless first.is_a?(Hash)

      results = cheap_checks
      baseline, dependencies = prepare_dependencies(first, results)
      results << execution_gap_result("execution_inputs", baseline) unless baseline.is_a?(String)
      results.concat(costly_checks(results))
      finish(results, "#{baseline}|#{dependencies}", settled_inputs(dependencies))
    end

    private

    # No report can exist without a writable output directory, so this stops the run (exit 3, message on stderr).
    # Command logs are switched on only after this, so no earlier command can write outside the verified root.
    def prepare_output_directory
      FileUtils.mkdir_p(File.join(@output_directory, "logs"), mode: 0o700)
      @commands.log_directory = File.join(@output_directory, "logs") if @own_commands
    rescue SystemCallError => e
      raise ExecutionGap, "output directory #{@output_directory} cannot be created: #{e.class}"
    end

    def cheap_checks
      return [empty_change_set] if @repository.changes.empty?

      [["protected_paths", -> { Checks::ProtectedPaths.new(repository: @repository).call }],
       ["check_policy_changes", -> { Checks::CheckPolicyChanges.new(repository: @repository).call }],
       ["base_snapshot", -> { Checks::BaseSnapshot.new(repository: @repository, base: @options.base).call }],
       ["readme_update", -> { Checks::ReadmeUpdate.new(repository: @repository).call }],
       ["dco_signoff", -> { Checks::Signoff.new(repository: @repository).call }],
       ["spdx_headers", -> { Checks::SpdxHeaders.new(repository: @repository, head: @options.head).call }],
       ["diff_check", lambda {
         Checks::Whitespace.new(repository: @repository, command_runner: @commands, head: @options.head).call
       }]].map { |name, step| guarded(name, &step) }
    end

    # A check that raises is incomplete, never a traceback and never a pass.
    def guarded(name)
      yield
    rescue ExecutionGap, UnverifiableInput => e
      execution_gap_result(name, e)
    end

    def execution_gap_result(name, error)
      CheckResult.new(name: name, status: :incomplete, reason: error.respond_to?(:message) ? error.message : error.to_s)
    end

    def capture_inputs
      yield
    rescue ExecutionGap, UnverifiableInput => e
      e
    end

    def empty_change_set
      CheckResult.new(name: "change_inventory", status: :failed,
                      reason: "empty change set between merge base and head")
    end

    # Stops at the first costly check that fails or is incomplete; later stages are recorded as not run.
    def costly_checks(cheap)
      blocked = stops?(cheap)
      costly_steps.map do |name, step|
        next skipped(name) if blocked

        guarded(name, &step).tap { |result| blocked = stops?([result]) }
      end
    end

    def stops?(results)
      results.any? { |result| %i[failed incomplete].include?(result.status) }
    end

    def costly_steps
      steps = [["rubocop", -> { Checks::Rubocop.new(command_runner: @commands).call }],
               ["harness_specs", -> { rspec("harness_specs", ["spec/script/preflight"]) }]]
      return steps unless @options.mode == "full"

      steps << ["full_suite", -> { rspec("full_suite", []) }]
      steps + unimplemented
    end

    def rspec(name, paths)
      Checks::Rspec.new(name: name, command_runner: @commands, paths: paths,
                        report_directory: File.join(@output_directory, "logs")).call
    end

    def unimplemented
      %w[changed_method_dogfood operator_expansion_dogfood registry_tiers_contract].map do |name|
        [name, -> { CheckResult.new(name: name, status: :not_run, reason: "not implemented in this version") }]
      end
    end

    def skipped(name)
      CheckResult.new(name: name, status: :not_run, reason: "skipped: an earlier check did not pass")
    end

    # Dependency preparation contract: after the cheap checks passed, `bundle list` runs. It may create the ignored
    # lockfile in a fresh checkout. The "before" fingerprint is the one taken after that step, and only the
    # lockfile appearing is accepted as a difference from the one taken before it. Anything else that
    # changed (a tracked file, the tree, any other input) is a gap.
    def prepare_dependencies(first, results)
      return [@inputs.digest_of(first), nil] if stops?(results)

      dependencies = capture_inputs { @inputs.dependency_digest }
      return [dependencies, nil] unless dependencies.is_a?(String)

      second = capture_inputs { @inputs.snapshot }
      return [second, nil] unless second.is_a?(Hash)

      baseline = capture_inputs { @inputs.baseline(first, second) }
      [baseline, dependencies]
    end

    def settled_inputs(dependencies)
      @repository.verify_identity!
      passive = @inputs.digest
      "#{passive}|#{@inputs.dependency_digest if dependencies.is_a?(String)}"
    rescue UnverifiableInput, ExecutionGap
      "changed-during-run"
    end

    # Always returns a report. If the report cannot be written, the verdict becomes incomplete and the
    # Markdown still goes to stdout.
    def finish(results, before, after)
      report = build_report(results, before, after)
      report.write(@output_directory)
      report
    rescue SystemCallError, IOError => e
      failed = results + [CheckResult.new(name: "report_output", status: :incomplete,
                                          reason: "report could not be written: #{e.class}")]
      build_report(failed, before, after)
    end

    def build_report(results, before, after)
      Report.new(options: @options, merge_base: @repository.merge_base, results: results, run_id: @run_id,
                 tree_before: before, tree_after: after, environment: environment, changes: @repository.changes,
                 provenance: provenance)
    end

    def environment
      { ruby: RUBY_VERSION, platform: RUBY_PLATFORM, ruby_engine: RUBY_ENGINE }
    end

    def provenance
      { origin_main_snapshot: @repository.origin_main_snapshot,
        trusted_policy_sha256: Checks::ProtectedPaths.new(repository: @repository).policy_digest,
        output_directory: @output_directory,
        rerun_command: "ruby script/preflight --base #{@options.base} --head #{@options.head} " \
                       "--base-ref #{@options.base_ref} --mode #{@options.mode}",
        commands: @commands.respond_to?(:history) ? @commands.history : [] }
    end
  end
end
