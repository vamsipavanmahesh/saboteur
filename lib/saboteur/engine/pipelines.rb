# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # The two run pipelines: in-process (boot, coverage, workers) and the
    # --test-command external mode (#140).
    module Pipelines
      # The in-process pipeline: boot the target, mutate under coverage, and
      # clean the workers up however the run ends.
      def run_pipeline(ignore_list, started)
        return call_external(ignore_list, started) if external_command?

        boot = Boot.new(config, hooks)
        begin
          integration, files, load_lines = boot_target(boot)
          @rails = boot.rails
          subjects, scope = select_subjects(files)
          results = subjects.empty? ? [] : mutate(subjects, files, integration, scope, ignore_list, load_lines:)
          @diagnostics.warnings.concat(ignore_list.apply(results, unscoped_digests: @unscoped_digests))
          build_report(results, subjects, scope, started)
        ensure
          # Cleanup runs however the call ends - a partway boot failure, no
          # subjects, no runnable work - so a host embedding Engine never
          # holds worker copies until process exit. Idempotent; the Rails
          # profile's at_exit handler stays the fallback for abrupt exit.
          begin
            @coverage_guard&.resume # an embedded host gets its coverage back (#254)
          ensure
            safely_cleanup_workers(boot.rails)
          end
        end
      end

      # The --test-command pipeline (#140): no boot, no coverage, no
      # baseline - every mutant runs the command on the mutated tree,
      # serially, with no sandbox. The command is arbitrary user code.
      def call_external(ignore_list, started)
        @diagnostics.inform("external test command: #{config['test_command']} (serial, no coverage, unsandboxed)")
        files = config.included_files
        subjects, scope = select_subjects(files)
        results = subjects.empty? ? [] : mutate_external(subjects, scope, ignore_list)
        @diagnostics.warnings.concat(ignore_list.apply(results, unscoped_digests: @unscoped_digests))
        build_report(results, subjects, scope, started)
      end

      def mutate_external(subjects, scope, ignore_list)
        map = Selection::ExternalTestMap.new
        scheduler = Scheduler.new(config:, runner: external_runner, map:,
                                  reevaluator: Execution::Reevaluator.new(config["reeval"],
                                                                          whole_file: config["whole_file"]),
                                  diagnostics: @diagnostics, deadline: budget_deadline, verify_loaded: false)
        lists = candidate_lists(subjects, scope, map)
        work = subjects.zip(lists).reject { |_, list| list.empty? }
        return [] if work.empty?

        runnable_subjects, runnable_lists = work.transpose
        run_candidates(runnable_subjects, runnable_lists, scheduler, nil, ignore_list)
      end

      def external_command? = !config["test_command"].to_s.empty?

      def external_runner = Execution::ExternalRunner.new(command: config["test_command"], root: @root)
    end
  end
end
