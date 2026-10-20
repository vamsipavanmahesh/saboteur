# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/baseline/comparison"
require "saboteur/baseline/identity"
require "saboteur/baseline/manifest"

RSpec.describe Saboteur::Baseline::Manifest do
  let(:identity) do
    Saboteur::Baseline::Identity.new(subject: person_subject, mutation: comparison_mutation,
                                     root: File.dirname(person_subject.file))
  end
  let(:candidate) { identity.entry.merge("status" => "survived", "kill_cause" => nil) }
  let(:metadata) do
    { "generator" => { "version" => Saboteur::VERSION }, "runtime" => { "engine" => "ruby" },
      "config" => { "seed" => 1 }, "scope" => { "include" => ["lib/**/*.rb"] },
      "snapshot" => { "digest" => "a" * 64 }, "subjects" => [["person.rb", "Person#adult?"]],
      "complete" => true, "issues" => [] }
  end
  let(:acceptance) { { "id" => identity.id, "context" => identity.context, "reason" => "equivalent" } }
  let(:document) do
    { "format" => 1, "identity_version" => 1, "metadata" => metadata,
      "candidates" => [candidate], "accepted" => [acceptance] }
  end

  def refuse(changed, message)
    expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, message)
  end

  it "wraps a value JSON cannot hold in the JSON message with the cause" do
    refuse(document.merge("metadata" => metadata.merge("config" => { "seed" => Float::NAN })), /\Abaseline JSON: .+/)
  end

  it "wraps a document nested too deeply the same way" do
    deep = (1..200).reduce([]) { |inner, _| [inner] }
    refuse(document.merge("metadata" => metadata.merge("config" => deep)), /\Abaseline JSON: /)
  end

  it "needs complete evidence and no issues, each on its own" do
    refuse(document.merge("metadata" => metadata.merge("issues" => ["x"])), "baseline: invalid incomplete evidence")
    refuse(document.merge("metadata" => metadata.merge("complete" => false)), "baseline: invalid incomplete evidence")
    refuse(document.merge("metadata" => metadata.merge("complete" => "true")), "baseline: invalid incomplete evidence")
  end

  it "names the metadata section that is missing, empty or not a hash" do
    %w[generator runtime config scope snapshot].each do |name|
      refuse(document.merge("metadata" => metadata.merge(name => {})), "baseline: invalid metadata #{name}")
      refuse(document.merge("metadata" => metadata.merge(name => "x")), "baseline: invalid metadata #{name}")
    end
  end

  it "names the list that holds a duplicate id" do
    refuse(document.merge("candidates" => [candidate, candidate]), "baseline: invalid duplicate candidates")
    refuse(document.merge("accepted" => [acceptance, acceptance]), "baseline: invalid duplicate accepted")
  end

  it "takes a context only as a whole lowercase 64-character hex digest" do
    ["#{'a' * 64}x", "x#{'a' * 64}", "#{'a' * 64}\nx", "x\n#{'a' * 64}", "A" * 64, "a" * 63, 1].each do |bad|
      refuse(document.merge("candidates" => [candidate.merge("context" => bad)],
                            "accepted" => [acceptance.merge("context" => bad)]), "baseline: invalid context")
    end
  end
end

RSpec.describe Saboteur::Baseline::Comparison do
  it "adds the re-propose hint to the issues and reports incompatible inputs" do
    baseline = { "compatibility" => { "scope" => "a" }, "accepted" => [], "candidates" => [] }
    current = { "compatibility" => { "scope" => "b" }, "issues" => ["earlier"], "candidates" => [], "complete" => true }
    result = described_class.new(baseline:, current:)
    hint = "baseline inputs or operator policy changed; re-propose with baseline propose"
    expect(result.issues).to eq(["earlier", hint])
    expect([result.state, result.exit_code]).to eq(["incompatible", 2])
  end
end

RSpec.describe Saboteur::Baseline::Identity do
  it "records an edit's original text and replacement as hex of their bytes" do
    source = person_subject.file_source
    at = source.index(">=")
    edit = Saboteur::MutationSource::Edit.new(file: person_subject.file, start_byte: at, end_byte: at + 2,
                                              replacement: "é<")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: person_subject.id, operator: "x", edits: [edit])
    found = described_class.new(subject: person_subject, mutation:, root: File.dirname(person_subject.file))
    expect(found.entry["identity"].last).to eq([[at - person_subject.start_byte, at + 2 - person_subject.start_byte,
                                                 ">=".unpack1("H*"), "c3a93c"]])
  end
end
