# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# README ("A score that tells the truth"): "kills split by cause (`kills: 7 by
# a failed assertion, 1 by a crash`)". phase1_spec pins one operator through
# --verbose; this runs the whole people fixture and checks that the printed
# split, the crash classes and the per-operator line all agree with the
# cause recorded on every killed mutant in the JSON report.
RSpec.describe "kills split by cause (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("people"), "--all", "--verbose") }
  let(:killed) { mutants(run).select { |m| m["status"] == "Killed" } }

  def crash_reasons
    killed.map { |m| m["statusReason"] }.grep(/\Acrash: /)
  end

  it "prints the split of every kill into failed assertions and crashes" do
    assertions = killed.count { |m| m["statusReason"] == "assertion" }

    expect(assertions).to be_positive
    expect(crash_reasons).not_to be_empty
    expect(assertions + crash_reasons.size).to eq(killed.size)
    expect(run.out).to include("kills: #{assertions} by a failed assertion, #{crash_reasons.size} by a crash (")
  end

  it "names the crash classes, most frequent first, with their counts" do
    counts = crash_reasons.map { |reason| reason.delete_prefix("crash: ") }.tally.sort_by { |_, count| -count }
    listed = counts.map { |name, count| "#{name} #{count}" }.join(", ")

    expect(run.out).to include("by a crash (#{listed})")
  end

  it "lists the operators that kill by crashing, with crash kills out of all their kills" do
    by_operator = killed.group_by { |m| m["mutatorName"] }.filter_map do |operator, kills|
      crashes = kills.count { |m| m["statusReason"].start_with?("crash: ") }
      "#{operator} #{crashes} of #{kills.size}" if crashes.positive?
    end

    expect(by_operator).to include("body_raise 7 of 7")
    expect(run.out.lines.map(&:chomp)).to include("crash kills by operator: #{by_operator.join(', ')}")
  end
end
