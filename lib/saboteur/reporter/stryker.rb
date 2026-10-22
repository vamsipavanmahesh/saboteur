# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "agent_incomplete"

module Saboteur
  module Reporter
    # JSON in the open mutation-testing-report-schema (schemaVersion 2), as
    # read by the Stryker dashboard and mutation-testing-elements.
    class Stryker
      SCHEMA_VERSION = "2"
      THRESHOLDS = { high: 80, low: 60 }.freeze

      def initialize(path)
        @path = path
      end

      def call(report, exit_cause: nil, score_gates: nil)
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.generate(self.class.build(report, exit_cause: exit_cause, score_gates: score_gates)))
      end

      # Tests are listed once under testFiles with short ids; mutants refer to
      # them by id in killedBy/coveredBy instead of repeating full test names.
      def self.build(report, exit_cause: nil, score_gates: nil)
        test_ids = test_index(report.results)
        files = report.results.group_by { |result| result.subject.file }.to_h do |file, results|
          [relative(file, report.root), file_entry(results, test_ids)]
        end
        {
          schemaVersion: SCHEMA_VERSION,
          thresholds: THRESHOLDS,
          projectRoot: report.root,
          files: files,
          testFiles: test_files(test_ids),
          skippedSubjects: skipped_subjects(report),
          earlyStop: early_stop(report),
          rejectedKills: report.rejected_kills,
          warnings: report.warnings,
          framework: { name: "saboteur", version: VERSION },
          saboteur: saboteur_enrichment(report, exit_cause, score_gates)
        }.merge(report_config(report))
      end

      # The run's recorded settings: the seed, and the --since ref of a diff
      # run, so a consumer can tell a diff-scoped score from a project one.
      def self.report_config(report)
        config = {}
        config[:seed] = report.seed if report.seed
        config[:since] = report.since if report.diff? && report.since
        config.empty? ? {} : { config: config }
      end

      # saboteur-namespaced keys beyond Stryker's schema: findings and
      # scores, then the optional policy, shard, exit-cause and memory keys.
      def self.saboteur_enrichment(report, exit_cause, score_gates = nil)
        { findings: Findings.build(report), complete: Agent::Incomplete.complete?(report), scores: scores(report),
          inlineSuppressions: inline_audit(report) }
          .merge(operatorPolicy: report.operator_policy).merge(shard(report))
          .merge(exit_cause ? { exitCause: exit_cause } : {})
          .merge(report.memory ? { memory: report.memory } : {})
          .merge(score_gates ? { scoreGates: score_gates } : {})
      end

      def self.shard(report)
        report.shard ? { shard: report.shard.to_h } : {}
      end

      def self.inline_audit(report)
        report.inline_suppressions.map { |entry| entry.merge(file: relative(entry[:file], report.root)) }
      end

      # Score with its assertion and crash shares, for all mutants and without
      # the whole-body ones (body_nil, body_true, body_false, body_raise).
      def self.scores(report)
        { all: report.score_breakdown.to_h, withoutWholeBodyMutants: report.fine_score_breakdown.to_h }
      end

      # nil for a run that covered its whole selection.
      def self.early_stop(report)
        stop = report.early_stop
        return unless stop

        { reason: stop.reason, unreachedSubjects: stop.unreached, truncatedSubjects: truncated_subjects(stop),
          unverifiedSubjects: stop.unverified }
      end

      def self.truncated_subjects(stop)
        stop.truncated.map { |entry| { subject: entry[:subject], omittedMutants: entry[:omitted] } }
      end

      def self.skipped_subjects(report)
        report.skipped_subjects.map do |subject, reason|
          { subject: subject.id, file: relative(subject.file, report.root), line: subject.start_line, reason: reason }
        end
      end

      def self.test_index(results)
        names = results.flat_map { |result| result.covered_by + result.killed_by + result.executed.to_a }.uniq.sort
        names.each_with_index.to_h { |name, index| [name, index.to_s] }
      end

      # RSpec ids look like "./spec/a_spec.rb[1:2]"; anything else is grouped
      # under an empty path.
      def self.test_files(test_ids)
        test_ids.group_by { |name, _| name[%r{\A\.?/?(.+?\.rb)\[}, 1].to_s }.transform_values do |pairs|
          { tests: pairs.map { |name, id| { id: id, name: name } } }
        end
      end

      def self.file_entry(results, test_ids)
        source = results.first.subject.file_source.dup.force_encoding(Encoding::UTF_8)
        { language: "ruby", source: source.scrub,
          mutants: results.map { |result| mutant(result, source, test_ids) } }
      end

      def self.mutant(result, source, test_ids)
        entry = {
          id: result.digest,
          subject: result.subject.id,
          mutatorName: result.mutation.operator,
          replacement: result.mutation.edits.map(&:replacement).join(" | "),
          location: location(result.mutation.edits.first, source),
          status: status(result),
          static: false
        }
        entry.merge(optional_fields(result, test_ids))
      end

      def self.optional_fields(result, test_ids)
        {
          # A rejected kill is a verdict, not a tool error: the tests failed
          # but also fail with the method unchanged. Flag it per mutant;
          # the top-level rejectedKills stays a bare count (#375).
          rejectedKill: (true if result.rejected_kill?),
          statusReason: status_reason(result),
          # Why the survivor is worth a look, as a label only: scores and
          # the exit code never change (#192).
          classification: SurvivorClassification.label(result),
          # Additive (#1286): confirmed, killed_by_confirmation or unconfirmed.
          # An unconfirmed survivor reports Ignored: outside the score.
          confirmation: result.confirmation_state,
          # Additive (#1290): whether the mutated expression ever produced a
          # different value from the original; absent when not probed.
          valueDiffered: result.value_differed,
          creditedTest: result.credited_test&.then { |name| test_ids.fetch(name) },
          killedBy: result.killed_by.map { |name| test_ids.fetch(name) }.then { |ids| ids.empty? ? nil : ids },
          coveredBy: result.covered_by.map { |name| test_ids.fetch(name) }.then { |ids| ids.empty? ? nil : ids },
          # Which of the covering tests actually ran against the mutant; absent
          # when the run did not record them (a reused result, an older worker).
          executed: result.executed.to_a.map { |name| test_ids.fetch(name) }.then { |ids| ids.empty? ? nil : ids },
          duration: result.runtime && (result.runtime * 1000).round
        }.compact
      end

      def self.status(result)
        case result.status
        when :killed then "Killed"
        when :survived then result.unconfirmed? ? "Ignored" : "Survived"
        when :timeout then "Timeout"
        when :error, :resource_limit then "RuntimeError"
        when :skipped then result.reason&.start_with?("no coverage") ? "NoCoverage" : "Ignored"
        # The schema has no status for "ran, but no test can observe a
        # change here", nor for a verdict the budget left unchecked.
        # Ignored with the reason is the honest mapping.
        when :ran_at_load, :unreachable, :unverified then "Ignored"
        end
      end

      def self.status_reason(result)
        return "todo: #{result.triage_reason}" if result.triage_state == "todo"
        # The "ignored: " prefix is a public contract consumers classify by
        # (#304 CI): accepted_equivalent stays byte-identical to a plain
        # ignore, and only wont_fix adds a suffix after the reason.
        return "ignored: #{result.ignored} (wont_fix)" if result.triage_state == "wont_fix"
        return "ignored: #{result.ignored}" if result.ignored
        return "unconfirmed: #{result.unconfirmed_reason}" if result.unconfirmed?
        return "resource limit: #{result.reason}" if result.status == :resource_limit
        return result.crash_kill? ? "crash: #{result.kill_cause}" : result.kill_cause if result.kill_cause

        reason = result.reason.to_s.strip
        reason.empty? ? nil : reason
      end

      def self.location(edit, source)
        { start: position(source, edit.start_byte), end: position(source, edit.end_byte) }
      end

      # 1-based line and column; column counts characters, not bytes.
      def self.position(source, byte_offset)
        before = source.byteslice(0, byte_offset).force_encoding(Encoding::UTF_8).scrub
        line = before.count("\n") + 1
        column = before.size - (before.rindex("\n") || -1)
        { line: line, column: column }
      end

      def self.relative(file, root)
        file.delete_prefix("#{root}/")
      end
    end
  end
end
