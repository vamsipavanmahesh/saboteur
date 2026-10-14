# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"

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

      def call(report, exit_cause: nil)
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.generate(self.class.build(report, exit_cause: exit_cause)))
      end

      # Tests are listed once under testFiles with short ids; mutants refer to
      # them by id in killedBy/coveredBy instead of repeating full test names.
      def self.build(report, exit_cause: nil)
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
          saboteur: { findings: Findings.build(report), scores: scores(report),
                      inlineSuppressions: inline_audit(report) }
                     .merge(operatorPolicy: report.operator_policy).merge(exit_cause ? { exitCause: exit_cause } : {})
        }.merge(report.seed ? { config: { seed: report.seed } } : {})
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
        stop && { reason: stop.reason, unreachedSubjects: stop.unreached }
      end

      def self.skipped_subjects(report)
        report.skipped_subjects.map do |subject, reason|
          { subject: subject.id, file: relative(subject.file, report.root), line: subject.start_line, reason: reason }
        end
      end

      def self.test_index(results)
        names = results.flat_map { |result| result.covered_by + result.killed_by }.uniq
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
          statusReason: status_reason(result),
          killedBy: result.killed_by.map { |name| test_ids.fetch(name) }.then { |ids| ids.empty? ? nil : ids },
          coveredBy: result.covered_by.map { |name| test_ids.fetch(name) }.then { |ids| ids.empty? ? nil : ids },
          duration: result.runtime && (result.runtime * 1000).round
        }.compact
      end

      def self.status(result)
        case result.status
        when :killed then "Killed"
        when :survived then "Survived"
        when :timeout then "Timeout"
        when :error, :resource_limit then "RuntimeError"
        when :skipped then result.reason&.start_with?("no coverage") ? "NoCoverage" : "Ignored"
        # The schema has no status for "ran, but no test can observe a
        # change here". Ignored with the reason is the honest mapping.
        when :ran_at_load, :unreachable then "Ignored"
        end
      end

      def self.status_reason(result)
        return "ignored: #{result.ignored}" if result.ignored
        return "resource limit: #{result.reason}" if result.status == :resource_limit
        return result.crash_kill? ? "crash: #{result.kill_cause}" : result.kill_cause if result.kill_cause

        result.reason.to_s.lines.first&.strip
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
