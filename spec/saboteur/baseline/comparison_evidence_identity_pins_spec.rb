# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "saboteur/baseline/comparison"
require "saboteur/baseline/evidence"
require "saboteur/baseline/identity"

RSpec.describe Saboteur::Baseline::Comparison do
  let(:before) do
    { "compatibility" => { "scope" => "project" },
      "accepted" => [{ "id" => "a", "context" => "old", "reason" => "gap" },
                     { "id" => "b", "context" => "old", "reason" => "gap" }],
      "candidates" => [] }
  end

  def compare(candidates, baseline: before)
    current = baseline.merge("complete" => true, "issues" => [], "candidates" => candidates)
    described_class.new(baseline:, current:)
  end

  def accepted(id) = { "id" => id, "status" => "survived", "context" => "old" }

  it "asks for review when only a new survivor is found" do
    result = compare([accepted("a"), accepted("b"), accepted("c")])
    expect([result.categories["new"].size, result.categories["changed"].size, result.categories["unmatched"].size])
      .to eq([1, 0, 0])
    expect(result.state).to eq("review_required")
  end

  it "asks for review when only an accepted survivor changed its context" do
    result = compare([accepted("a").merge("context" => "other"), accepted("b")])
    expect([result.categories["new"].size, result.categories["changed"].size, result.categories["unmatched"].size])
      .to eq([0, 1, 0])
    expect(result.state).to eq("review_required")
  end

  it "asks for review when only an accepted survivor is no longer found" do
    result = compare([accepted("a"), { "id" => "z", "status" => "killed" }])
    expect([result.categories["new"].size, result.categories["changed"].size, result.categories["unmatched"].size])
      .to eq([0, 0, 1])
    expect(result.state).to eq("review_required")
  end

  it "lists a category by file, then subject, then id, treating a missing identity as empty" do
    entry = lambda do |id, file, subject|
      { "id" => id, "status" => "survived", "context" => "x", "identity" => [1, file, subject] }
    end
    result = compare([entry.call("9", "b.rb", "A#m"), entry.call("2", "a.rb", "Z#m"), entry.call("5", "a.rb", "A#m"),
                      entry.call("1", "a.rb", "A#m"), { "id" => "0", "status" => "survived", "context" => "x" }])
    expect(result.categories["new"].map { |item| item["id"] }).to eq(%w[0 1 5 2 9])
  end
end

RSpec.describe Saboteur::Baseline::Identity do
  def identity_for(edits)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: person_subject.id, operator: "x", edits:)
    described_class.new(subject: person_subject, mutation:, root: File.dirname(person_subject.file))
  end

  def edit(from, to)
    Saboteur::MutationSource::Edit.new(file: person_subject.file, start_byte: from, end_byte: to, replacement: "z")
  end

  it "orders edits by start and then end, so an insertion beside a replacement validates either way round" do
    at = person_subject.file_source.index(">=")
    base = person_subject.start_byte
    after = identity_for([edit(at + 2, at + 2), edit(at, at + 2)]).entry["identity"].last
    expect(after.map { |item| item.first(2) }).to eq([[at - base, at + 2 - base], [at + 2 - base, at + 2 - base]])
    before = identity_for([edit(at, at + 2), edit(at, at)]).entry["identity"].last
    expect(before.map { |item| item.first(2) }).to eq([[at - base, at - base], [at - base, at + 2 - base]])
  end
end

RSpec.describe Saboteur::Baseline::Evidence do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end
  let(:document) do
    file = File.join(@root, "probe.rb")
    File.write(file, "class Probe; def value; 1; end; end")
    subject = Saboteur::SubjectFinder.new.call(file).subjects.first
    mutation = Saboteur::MutationSource::Builtin.new.mutations_for(subject).first
    text = subject.apply(mutation.edits)
    capture = Saboteur::Baseline::RunEvidence.new(config: Saboteur::Config.new({}, root: @root))
    capture.plan([subject], [[[mutation, text]]])
    result = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :survived, mutated_source: text)
    JSON.parse(JSON.generate(capture.finish(results: [result], stable_suite: true, skipped_subjects: {},
                                            generation_events: [], omissions: [])))
  end

  it "names the list that is not an array" do
    { "generation_events" => "generation events", "planned" => "candidate plan", "candidates" => "candidates" }
      .each do |field, name|
      expect { described_class.new(document.merge(field => "x")) }
        .to raise_error(Saboteur::ConfigError, "baseline #{name}"), field
    end
  end

  it "wraps a structural error in the evidence message with the cause" do
    bare = document["candidates"].map { |entry| entry.slice("id", "identity", "context") }
    expect { described_class.new(document.merge("candidates" => bare)) }
      .to raise_error(Saboteur::ConfigError, /\Abaseline evidence: key not found: "status"/)
  end

  it "lists each accepted entry as id, context and reason, in that order" do
    entry = described_class.new(document).manifest(reasons: "why")["accepted"].first
    expect(entry.keys).to eq(%w[id context reason])
    expect(entry["reason"]).to eq("why")
  end
end
