# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Decision logic for script/bench-corpus (#652), kept apart so specs can
# exercise it without cloning any project.

require "json"

module BenchCorpus
  # A survivor this many lines from a fixed hunk still counts as "near".
  NEAR = 5
  NOT_DETECTED = %w[Survived NoCoverage].freeze

  module_function

  # Parent-side line ranges per file from `git diff -U0 PARENT FIX`. A pure
  # insertion has no parent line, so it claims the line it follows and the
  # line it precedes.
  def hunks(diff)
    file = nil
    diff.each_line.with_object(Hash.new { |h, k| h[k] = [] }) do |line, found|
      file = line.sub(%r{\A--- (a/)?}, "").strip if line.start_with?("--- ")
      file = nil if file == File::NULL
      next unless file && (match = line.match(/\A@@ -(\d+)(?:,(\d+))? /))

      start = match[1].to_i
      count = (match[2] || "1").to_i
      found[file] << (count.zero? ? (start..(start + 1)) : (start..(start + count - 1)))
    end
  end

  # :catch_exact, :catch_near, :miss or :no_mutants for one fix.
  def classify(mutants, ranges)
    return :no_mutants if mutants.empty?

    open = mutants.select { |mutant| NOT_DETECTED.include?(mutant.fetch("status")) }
    lines = open.map { |mutant| span(mutant) }
    return :catch_exact if lines.any? { |from, to| ranges.any? { |r| from <= r.end && to >= r.begin } }
    return :catch_near if lines.any? { |from, to| ranges.any? { |r| from <= r.end + NEAR && to >= r.begin - NEAR } }

    :miss
  end

  # The strongest verdict across the fix's files.
  def verdict(per_file)
    order = %i[catch_exact catch_near miss no_mutants]
    order.find { |kind| per_file.value?(kind) } || :no_mutants
  end

  def span(mutant)
    location = mutant.fetch("location")
    [location.dig("start", "line"), location.dig("end", "line")]
  end

  def table(rows)
    lines = ["| Project | Fix | Verdict | Expected | Mutants | Not detected |", "|---|---|---|---|---:|---:|"]
    rows.each do |row|
      lines << "| #{row[:name]} | #{row[:fix][0, 8]} | #{row[:verdict]} | #{row[:expected]} | " \
               "#{row[:mutants]} | #{row[:open]} |"
    end
    caught = rows.count { |row| row[:verdict].to_s.start_with?("catch") }
    (lines + ["", "Caught #{caught} of #{rows.size}."]).join("\n")
  end
end
