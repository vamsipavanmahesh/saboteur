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

      def call(report)
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.pretty_generate(self.class.build(report)))
      end

      def self.build(report)
        files = report.results.group_by { |result| result.subject.file }.to_h do |file, results|
          [relative(file, report.root), file_entry(results)]
        end
        {
          schemaVersion: SCHEMA_VERSION,
          thresholds: THRESHOLDS,
          projectRoot: report.root,
          files: files,
          framework: { name: "saboteur", version: VERSION }
        }
      end

      def self.file_entry(results)
        source = results.first.subject.file_source.dup.force_encoding(Encoding::UTF_8)
        { language: "ruby", source: source.scrub, mutants: results.map { |result| mutant(result, source) } }
      end

      def self.mutant(result, source)
        entry = {
          id: result.digest,
          mutatorName: result.mutation.operator,
          replacement: result.mutation.edits.map(&:replacement).join(" | "),
          location: location(result.mutation.edits.first, source),
          status: status(result),
          static: false
        }
        reason = status_reason(result)
        entry[:statusReason] = reason if reason
        entry[:killedBy] = result.killed_by if result.killed_by.any?
        entry[:coveredBy] = result.covered_by if result.covered_by.any?
        entry[:duration] = (result.runtime * 1000).round if result.runtime
        entry
      end

      def self.status(result)
        case result.status
        when :killed then "Killed"
        when :survived then "Survived"
        when :timeout then "Timeout"
        when :error then "RuntimeError"
        when :skipped then result.reason == "no coverage" ? "NoCoverage" : "Ignored"
        end
      end

      def self.status_reason(result)
        return "ignored: #{result.ignored}" if result.ignored

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
