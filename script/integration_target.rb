# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Decision logic for script/integration-target, kept in its own file so
# specs can exercise it without running the executable.

require "json"

module IntegrationTarget
  STATUS = { "Killed" => "killed", "Survived" => "survived", "Timeout" => "timeout",
             "RuntimeError" => "error", "NoCoverage" => "skipped", "Ignored" => "skipped" }.freeze

  module_function

  def counts(report_path)
    tally(mutants(JSON.parse(File.read(report_path, encoding: "UTF-8"))))
  end

  # Exit 3 has several causes: a boot or tool failure, an incomplete run
  # under --threshold, or a run whose executed mutants mostly errored. A
  # target's allow_error_fraction covers exactly the last one. The report
  # must be this run's own (the runner deletes any earlier one first),
  # carry the CLI's errorMajority marker, keep the errored fraction of
  # executed mutants inside the allowance, and hold no resource-limited
  # mutant: a resource cap is a sick machine, not a known error profile.
  def accept_error_majority?(code, allowance, report_path)
    return false unless code == 3 && allowance

    document = JSON.parse(File.read(report_path, encoding: "UTF-8"))
    all = mutants(document)
    actual = tally(all)
    executed = actual.values_at("killed", "survived", "timeout", "error").sum
    fraction = executed.zero? ? 1.0 : actual["error"].fdiv(executed)
    document.dig("saboteur", "exitCause") == "errorMajority" &&
      fraction > 0.5 && fraction <= allowance &&
      all.none? { |mutant| mutant["statusReason"].to_s.start_with?("resource limit") }
  rescue Errno::ENOENT, JSON::ParserError, KeyError
    false
  end

  # id => status of every mutant, for comparing two runs of one target.
  def verdicts(report_path)
    mutants(JSON.parse(File.read(report_path, encoding: "UTF-8"))).to_h do |mutant|
      [mutant.fetch("id"), mutant.fetch("status")]
    end
  end

  # [id, status in a, status in b] for every mutant whose verdict differs or
  # that only one run produced.
  def verdict_differences(left, right)
    (left.keys | right.keys).filter_map do |id|
      [id, left[id], right[id]] unless left[id] == right[id]
    end
  end

  def mutants(document)
    document.fetch("files").values.flat_map { |file| file.fetch("mutants") }
  end

  def tally(all)
    Hash.new(0).merge(all.map { |mutant| STATUS.fetch(mutant.fetch("status")) }.tally)
  end
end
