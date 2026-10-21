# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "ripper"

module Saboteur
  # The ignore ratchet: ignore entries only ever accumulate, and two kinds go
  # stale - the mutant is no longer generated (the code changed), and the
  # mutant was killed on the last full run (the entry hides a win). Staleness
  # is decided only from a full, complete report; anything else (a --since
  # run, an older report without the scope marker) leaves every entry
  # unknown, and unknown entries are never pruned.
  class IgnoreRatchet
    Entry = Data.define(:digest, :subject, :lines)

    Verdict = Data.define(:entry, :state, :note) do
      def stale? = state == :stale
    end

    GONE = "mutant no longer generated (code changed)"
    WON = "killed on the last full run (delete to lock the win)"

    ENTRY_START = /^\s*\w+\.mutation[\s(]/
    DIGEST = /mutation[\s(]+["']([0-9a-f]{8,64})["']/i
    SUBJECT = /subject:\s*["']([^"']+)["']/

    # An entry statement ends where the accumulated text parses; a trailing
    # comma or an open call keeps the scan going onto the next line.
    def self.entries_in(text)
      lines = text.lines
      lines.each_index.select { |i| lines[i].match?(ENTRY_START) }.map do |start|
        finish = (start...lines.size).find { |i| Ripper.sexp(lines[start..i].join) } || (lines.size - 1)
        statement = lines[start..finish].join
        Entry.new(digest: statement[DIGEST, 1], subject: statement[SUBJECT, 1], lines: start..finish)
      end
    end

    def initialize(ignore_text:, report:)
      @entries = self.class.entries_in(ignore_text)
      @report = report
    end

    # Why no verdict can be reached, nil when the report decides every entry.
    def undecidable_reason
      saboteur = @report["saboteur"] || {}
      return if saboteur["scope"] == "full" && saboteur["complete"] == true

      case saboteur["scope"]
      when nil then "the last report does not say whether it was a full run"
      when "full" then "the last full run did not judge every mutant"
      else "the last report is not a full run"
      end
    end

    def verdicts
      if (reason = undecidable_reason)
        return @entries.map { |entry| Verdict.new(entry:, state: :unknown, note: "unknown - #{reason}; not pruned") }
      end

      statuses = mutant_statuses
      @entries.map do |entry|
        status = entry.digest && statuses[entry.digest]
        if entry.digest.nil?
          Verdict.new(entry:, state: :unknown, note: "unknown - the entry could not be parsed; not pruned")
        elsif status.nil?
          Verdict.new(entry:, state: :stale, note: GONE)
        elsif status == "Killed"
          Verdict.new(entry:, state: :stale, note: WON)
        else
          Verdict.new(entry:, state: :live, note: nil)
        end
      end
    end

    # The ignore text minus the stale entries' lines: order, comments and
    # every live entry stay byte-identical.
    def pruned_text(text)
      cut = verdicts.select(&:stale?).flat_map { |v| v.entry.lines.to_a }
      text.lines.reject.with_index { |_, i| cut.include?(i) }.join
    end

    private

    def mutant_statuses
      @report.fetch("files", {}).flat_map { |_, entry| entry.fetch("mutants", []) }
             .to_h { |mutant| [mutant["id"], mutant["status"]] }
    end
  end
end
