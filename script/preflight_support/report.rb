# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "time"

module Preflight
  # Machine result and Markdown summary. The result names never say "approved" or "merge-ready".
  class Report
    SCHEMA_VERSION = 1
    MANUAL_OBLIGATIONS = [
      "Every claim in the PR body, README and comments is matched to code or a spec (manual, claim ledger).",
      "Default versus opt-in behavior is proven by a fixture, not by wording (manual).",
      "The live PR base is main and CI and the panel gate are green on this exact head (live check, not offline).",
      "Speed and memory claims carry the paired AB/BA evidence AGENTS.md requires (manual).",
      "Ticked checkboxes and quoted approvals are unverified until read against the maintainer's own words (manual)."
    ].freeze

    def initialize(options:, merge_base:, tree_before:, tree_after:, results:, environment:, run_id:, changes:,
                   provenance: {})
      @options = options
      @merge_base = merge_base
      @tree = [tree_before, tree_after]
      @results = results
      @environment = environment
      @run_id = run_id
      @changes = changes
      @provenance = provenance
    end

    # Without both identities nothing proves the findings belong to one stable input.
    def identity_missing?
      @tree.first.nil? || @tree.last.nil?
    end

    def invalidated?
      !@tree.first.nil? && !@tree.last.nil? && @tree.first != @tree.last
    end

    # Changed inputs and any evidence gap (incomplete check, missing identity) outrank a failed check. The findings
    # stay in the report, marked as belonging to a run whose inputs changed.
    def verdict
      statuses = @results.map(&:status)
      return "incomplete" if invalidated? || identity_missing? || statuses.include?(:incomplete)
      return "failed" if statuses.include?(:failed)
      return "incomplete" if @results.empty?
      return "partial" if @options.mode == "fast" || statuses.intersect?(%i[not_run review_required])

      "automatic_checks_passed"
    end

    def exit_code
      { "failed" => 1, "incomplete" => 3 }.fetch(verdict, 0)
    end

    def to_h
      { schema_version: SCHEMA_VERSION, run_id: @run_id, mode: @options.mode, verdict: verdict,
        invalidated_by: ("inputs changed during the run: findings are not trustworthy" if invalidated?),
        base: @options.base, head: @options.head, merge_base: @merge_base, base_ref: @options.base_ref,
        base_freshness: "unverified: offline snapshot, live main not consulted",
        provenance: @provenance,
        tree_digest_before: @tree.first, tree_digest_after: @tree.last,
        changed_files: @changes.map { |change| describe_change(change) },
        environment: @environment, checks: @results.map(&:to_h), manual_obligations: MANUAL_OBLIGATIONS }
    end

    def write(directory, root: directory)
      SafeOutput.make_directories(directory, root)
      SafeOutput.write_new(File.join(directory, "report.json"), JSON.pretty_generate(to_h), root)
      SafeOutput.write_new(File.join(directory, "report.md"), markdown, root)
    end

    def markdown
      lines = ["# Preflight #{@options.mode}: #{verdict}", "",
               "- head: #{@options.head}", "- base: #{@options.base}", "- merge base: #{@merge_base}", ""]
      lines << "Fast mode is partial by design. It never replaces full mode." if @options.mode == "fast"
      lines.push("| check | status | reason |", "| --- | --- | --- |")
      @results.each { |result| lines << "| #{result.name} | #{result.status} | #{cell(result.reason)} |" }
      lines << ""
      first = @results.find { |result| %i[failed incomplete].include?(result.status) }
      lines.push("First problem: #{first.name} - #{cell(first.reason)}", "") if first
      if @provenance.any?
        lines.push("Rerun: #{@provenance[:rerun_command]}", "Logs and raw reports: #{@provenance[:output_directory]}",
                   "")
      end
      lines.push("Manual obligations (not checked by this tool):", *MANUAL_OBLIGATIONS.map { |item| "- #{item}" }, "")
      lines.join("\n")
    end

    private

    def describe_change(change)
      { status: change.status, path: change.path, old_mode: change.old_mode, new_mode: change.new_mode,
        old_blob: change.old_blob, new_blob: change.new_blob }
    end

    def cell(text)
      text.to_s.gsub(/[|`\r\n]/, " ").strip
    end
  end
end
