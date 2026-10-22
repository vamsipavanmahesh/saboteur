# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../execution/test_command_shape"

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
          integration, files, load_lines, load_methods = boot_target(boot)
          @rails = boot.rails
          subjects, scope = select_subjects(files, test_files: integration.test_files)
          results = if subjects.empty?
                      []
                    else
                      mutate(subjects, files, integration, scope, ignore_list,
                             load_lines:, load_methods:)
                    end
          warnings = ignore_list.apply(results, subjects: subjects,
                                                unscoped_digests: @unscoped_digests, full_run: unscoped_full_run?)
          @diagnostics.add_warnings(warnings)
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
        @diagnostics.inform("external test command: #{config['test_command']} " \
                            "(serial, no coverage, unsandboxed, mutants applied in a disposable copy)")
        if Execution::TestCommandShape.multi_file_ruby?(config["test_command"])
          @diagnostics.warn("use the framework's multi-file form (bin/rails test f1 f2, rspec f1 f2) or a " \
                            "shell loop (for f in ...; do ruby \"$f\" || exit 1; done)\n  " \
                            "the test command hands several test files to one ruby: ruby executes only " \
                            "the first, so the rest never run and their mutants silently survive (#611)")
        end
        files = config.included_files
        subjects, scope = select_subjects(files)
        results = subjects.empty? ? [] : mutate_external(subjects, scope, ignore_list)
        warnings = ignore_list.apply(results, subjects: subjects,
                                              unscoped_digests: @unscoped_digests, full_run: unscoped_full_run?)
        @diagnostics.add_warnings(warnings)
        build_report(results, subjects, scope, started)
      end

      def mutate_external(subjects, scope, ignore_list)
        runner = external_runner
        # One neutral run before any mutant exists: a command that fails on
        # the unchanged tree can never claim kills (#305). It answers to the
        # run budget with an ABSOLUTE deadline, admitted after the tree copy:
        # a budget already spent is a budget stop, not a command error.
        begin
          runner.preflight!(deadline: preflight_deadline, budget_deadline: budget_deadline)
        rescue BudgetPhaseTimeout => e
          return budget_phase_stop(e, subjects)
        end
        map = Selection::ExternalTestMap.new
        scheduler = Scheduler.new(config:, runner:, map:,
                                  reevaluator: Execution::Reevaluator.new(config["reeval"],
                                                                          whole_file: config["whole_file"]),
                                  diagnostics: @diagnostics, deadline: budget_deadline, verify_loaded: false)
        lists = candidate_lists(subjects, scope, map)
        work = subjects.zip(lists).reject { |_, list| list.empty? }
        return [] if work.empty?

        runnable_subjects, runnable_lists = work.transpose
        begin
          warn_unless_mutants_visible(runner, runnable_subjects.first)
        rescue BudgetPhaseTimeout => e
          return budget_phase_stop(e, subjects)
        end
        run_candidates(runnable_subjects, runnable_lists, scheduler, nil, ignore_list)
      ensure
        runner&.close
      end

      # Warn loudly when the command cannot see mutants at all: an
      # anchored or never-loaded file reads as 100 % survivors (#441).
      def warn_unless_mutants_visible(runner, subject)
        warning = runner.visibility_check(subject: subject, deadline: preflight_deadline,
                                          budget_deadline: budget_deadline)
        @diagnostics.warn(warning) if warning
      end

      # "Full run" for ignore staleness (#1206): no --since diff, no --subject
      # filter, and no narrowed include (explicit file arguments replace the
      # configured include) - only then was every in-scope subject examined, so
      # an entry whose subject never appears really points at gone code. The
      # include nobody set counts as unscoped whether it is the generic
      # default or the Rails one a config-less app gets (#1255).
      def unscoped_full_run?
        !config["since"] && config["subjects"].empty? && default_include?
      end

      def default_include?
        config["include"] == Config::DEFAULTS["include"] ||
          (config["include"] == Config::RAILS_INCLUDE && !config.explicit?("include"))
      end

      def external_command? = !config["test_command"].to_s.empty?

      # The preflight's absolute monotonic deadline: its own
      # baseline_timeout slice, or the run budget's end, whichever is
      # sooner. Absolute, so the tree copy before admission cannot eat the
      # budget while the command still gets a full timeout (#305 Architect).
      def preflight_deadline
        own = Process.clock_gettime(Process::CLOCK_MONOTONIC) + config["baseline_timeout"]
        deadline = budget_deadline
        deadline ? [own, deadline].min : own
      end

      def external_runner = Execution::ExternalRunner.new(command: config["test_command"], root: @root)
    end
  end
end
