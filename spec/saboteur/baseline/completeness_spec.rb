# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/baseline/completeness"

RSpec.describe Saboteur::Baseline::Completeness do
  def evidence(**options)
    described_class.new(planned: %w[a b], results: [{ "id" => "a", "status" => "killed" },
                                                    { "id" => "b", "status" => "survived" }],
                        subjects: [["person.rb", "Person#adult?"]], stable_suite: true, stable_inputs: true,
                        skipped_subjects: [], omitted: [], generation_issues: [], **options)
  end

  it "requires every planned candidate exactly once with complete suite and input evidence" do
    value = evidence
    expect(value.complete?).to be(true)
    expect(value.issues).to eq([])
    expect(evidence(stable_suite: false).issues).to eq(["unchanged_suite_incomplete"])
    expect(evidence(stable_inputs: false).issues).to eq(["inputs_unverified"])
  end

  it "rejects empty scope, missing and extra results and duplicate planned or result identities" do
    expect(evidence(planned: [], results: []).issues).to include("empty_candidates")
    expect(evidence(subjects: []).issues).to include("empty_subjects")
    expect(evidence(planned: %w[a a b]).issues).to include("duplicate_candidates")
    expect(evidence(results: [{ "id" => "a", "status" => "killed" }]).issues).to include("missing_result:b")
    extra = [{ "id" => "a", "status" => "killed" }, { "id" => "b", "status" => "survived" },
             { "id" => "c", "status" => "killed" }]
    expect(evidence(results: extra).issues).to include("unexpected_result:c")
    extra[-1] = extra.first
    expect(evidence(results: extra).issues).to include("duplicate_results")
  end

  it "never considers errors, skips, resource limits, no coverage or unknown statuses complete" do
    %w[error resource_limit skipped no_coverage other].each do |status|
      value = evidence(results: [{ "id" => "a", "status" => status }, { "id" => "b", "status" => "killed" }])
      expect(value.complete?).to be(false)
      expect(value.issues).to eq(["unexecuted:a:#{status}"])
    end
    value = evidence(results: [{ "id" => "a", "status" => "timeout" }, { "id" => "b", "status" => "killed" }])
    expect(value.complete?).to be(true)
  end

  it "carries typed omissions, subject skips and generation defects independent of result counts" do
    value = evidence(skipped_subjects: ["person.rb:Person#unknown"], omitted: ["person.rb:Person#adult?:2"],
                     generation_issues: ["invalid_parser:source:person.rb", "apply_failed:source:person.rb"])
    expected = ["generation:apply_failed:source:person.rb", "generation:invalid_parser:source:person.rb",
                "omitted:person.rb:Person#adult?:2", "subject_skipped:person.rb:Person#unknown"]
    expect(value.issues).to eq(expected)
    expect(value.complete?).to be(false)
    expect(value.issues).to be_frozen
  end

  it "marks duplicate subjects ambiguous and returns unique deterministic reasons" do
    value = evidence(subjects: [["a.rb", "A#m"], ["a.rb", "A#m"]], generation_issues: %w[b a b])
    expect(value.issues).to eq(["duplicate_subjects", "generation:a", "generation:b"])
    expect(value.complete?).to be(false)
  end

  it "splits issues into hard blockers and soft gaps, gating proposability on blockers only" do
    value = described_class.new(planned: ["a"], results: [{ "id" => "a", "status" => "killed" }],
                                subjects: ["s"], stable_suite: true, stable_inputs: true,
                                skipped_subjects: ["probe.rb:Probe#other:no_tests"], omitted: ["probe.rb:2"],
                                generation_issues: [])
    expect(value).not_to be_complete
    expect(value).to be_proposable
    expect(value.gaps).to eq(["omitted:probe.rb:2", "subject_skipped:probe.rb:Probe#other:no_tests"])
    expect(value.blockers).to eq([])

    blocked = described_class.new(planned: ["a"], results: [{ "id" => "a", "status" => "killed" }],
                                  subjects: ["s"], stable_suite: false, stable_inputs: true,
                                  skipped_subjects: ["probe.rb:Probe#other:no_tests"], omitted: [],
                                  generation_issues: [])
    expect(blocked).not_to be_proposable
    expect(blocked.blockers).to eq(["unchanged_suite_incomplete"])
    expect(blocked.gaps).to eq(["subject_skipped:probe.rb:Probe#other:no_tests"])
  end
end
