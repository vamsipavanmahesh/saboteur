# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Runs one subject's candidates and returns their results. This is the
    # unit of work parallel workers will share out.
    #
    # Order of business: skip what cannot be run (refinements, not loaded,
    # shadowed, no covering test); the neutral check (unchanged method, its
    # tests must pass, its runtime sets the timeout); coarse mutants; fine
    # mutants only if no coarse mutant survived. Each mutant runs only the
    # tests that executed its edit, likeliest killers first.
    class Scheduler
      # A subject that passed its neutral check, with what its mutants need.
      # killers counts the tests that killed earlier mutants of this subject.
      Plan = Data.define(:subject, :tests, :timeout, :killers)

      # Tests that killed more earlier mutants first; otherwise keep the order.
      def self.prioritize(tests, killers)
        tests.sort_by.with_index { |id, index| [-killers.fetch(id, 0), index] }
      end

      def initialize(config:, runner:, map:, reevaluator:, diagnostics:)
        @config = config
        @runner = runner
        @map = map
        @reevaluator = reevaluator
        @diagnostics = diagnostics
      end

      def call(subject, candidates)
        return [] if candidates.empty?

        reason = subject.skip_reason || load_problem(subject)
        return skip_all(candidates, subject, reason) if reason

        tests = @map.tests_for(subject)
        return skip_all(candidates, subject, "no coverage") if tests.empty?

        timeout, reason = neutral_check(subject, tests)
        return skip_all(candidates, subject, reason, covered_by: tests) unless timeout

        run_candidates(Plan.new(subject:, tests:, timeout:, killers: Hash.new(0)), candidates)
      end

      private

      # Runs the subject's tests against the re-evaluated, unchanged method.
      # Returns [per-mutant timeout, nil] when they pass, else [nil, skip
      # reason]: a slow suite and a broken re-evaluation need different fixes.
      def neutral_check(subject, tests)
        baseline = @runner.run(subject: subject, text: subject.source, test_ids: tests,
                               timeout: @config["baseline_timeout"])
        note_leftovers(subject, "neutral check", baseline)
        if baseline.status == :survived
          return [[@config["timeout_factor"] * baseline.runtime, @config["timeout_min"]].max, nil]
        end

        detail = baseline.message.to_s.lines.first&.strip || "failed: #{baseline.failed_ids.first(3).join(', ')}"
        @diagnostics.warn("#{subject.id}: neutral check #{baseline.status}, #{detail}")
        [nil, baseline.status == :timeout ? "baseline timeout" : "baseline failure"]
      end

      def run_candidates(plan, candidates)
        coarse, fine = candidates.partition { |mutation, _| mutation.coarse }
        results = coarse.map { |mutation, text| execute(plan, mutation, text) }
        # A surviving coarse mutant means nothing checks the body, so the fine
        # mutants would only add noise. Not so when a rescue or else can
        # return a value of its own: fine mutants that make the body raise
        # can still be caught.
        if results.any?(&:survived?) && !plan.subject.recovers?
          return results + skip_all(fine, plan.subject, "coarse mutant survived", covered_by: plan.tests)
        end

        results + fine.map { |mutation, text| execute(plan, mutation, text) }
      end

      def execute(plan, mutation, text)
        tests = tests_for(plan, mutation)
        return skip_all([[mutation, text]], plan.subject, "no coverage").first if tests.empty?

        outcome = @runner.run(subject: plan.subject, text: text, test_ids: tests, timeout: plan.timeout,
                              mutation: mutation)
        result = MutantResult.new(subject: plan.subject, mutation: mutation, status: outcome.status,
                                  mutated_source: text, reason: outcome.message, runtime: outcome.runtime,
                                  killed_by: outcome.failed_ids, covered_by: tests, kill_cause: outcome.kill_cause)
        outcome.failed_ids.each { |id| plan.killers[id] += 1 }
        note_leftovers(plan.subject, "#{mutation.operator} #{result.digest}", outcome)
        @diagnostics.progress(result)
        result
      end

      # Coarse mutants replace the whole body: every test of the method. Fine
      # mutants: only the tests that executed the edited statement. Either
      # way, prior killers first, then the neutral check's fastest-first order.
      def tests_for(plan, mutation)
        tests = plan.tests
        unless mutation.coarse
          line_numbers = mutation.edits.flat_map { |edit| plan.subject.coverage_lines_for(edit) }.uniq
          tests &= @map.tests_for_lines(plan.subject.file, line_numbers)
        end
        self.class.prioritize(tests, plan.killers)
      end

      # The method saboteur would redefine must be the one Ruby is running.
      def load_problem(subject)
        owner = @reevaluator.resolve_owner(subject)
        target = subject.singleton ? owner.singleton_class : owner
        method = own_method(target, subject.name)
        return "method not loaded" unless method

        file, line = method.source_location
        return nil if file && Selection::CoverageMap.canonical(file) == subject.file && line == subject.start_line

        "shadowed definition (runtime method at #{file}:#{line})"
      rescue Error => e
        "owner not loaded: #{e.message}"
      end

      def own_method(target, name)
        return nil unless target.method_defined?(name) || target.private_method_defined?(name)

        method = target.instance_method(name)
        method = method.super_method while method && method.owner != target
        method
      end

      def note_leftovers(subject, what, outcome)
        return if outcome.leftover_pids.empty?

        @diagnostics.warn("#{subject.id} #{what}: killed #{outcome.leftover_pids.size} process(es) it left running")
      end

      def skip_all(candidates, subject, reason, covered_by: [])
        candidates.map do |mutation, text|
          MutantResult.new(subject: subject, mutation: mutation, status: :skipped, mutated_source: text,
                           reason: reason, covered_by: covered_by)
        end
      end
    end
  end
end
