# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "saboteur/baseline/workflow"

RSpec.describe Saboteur::Baseline::Acceptance do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end
  let(:config) { Saboteur::Config.new({}, root: @root) }
  let(:document) do
    file = File.join(@root, "probe.rb")
    File.write(file, "class Probe; def value; 1; end; end")
    subject = Saboteur::SubjectFinder.new.call(file).subjects.first
    mutation = Saboteur::MutationSource::Builtin.new.mutations_for(subject).first
    text = subject.apply(mutation.edits)
    capture = Saboteur::Baseline::RunEvidence.new(config: config)
    capture.plan([subject], [[[mutation, text]]])
    result = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :survived, mutated_source: text)
    capture.finish(results: [result], stable_suite: true, skipped_subjects: {}, generation_events: [], omissions: [])
  end
  let(:evidence) { Saboteur::Baseline::Evidence.new(document) }
  let(:store) do
    described_class.new(directory: File.join(@root, ".saboteur", "baseline-evidence"), protected_paths: [],
                        verify: ->(_) { true }, require_evidence: true)
  end

  def propose(manifest, name = "p")
    store.propose(document: manifest, evidence: evidence.document, proposal: File.join(@root, "#{name}.json"),
                  destination: File.join(@root, "#{name}-out.json"))
  end

  it "stores the given execution evidence in the record, in the returned value and in the proposal file" do
    record = propose(evidence.manifest)
    expect(record["execution"]).to eq(evidence.document)
    expect(JSON.parse(File.read(File.join(@root, "p.json")))["execution"]).to eq(evidence.document)
  end

  it "ignores the reasons written in the proposed manifest when it compares with the evidence" do
    expect { propose(evidence.manifest(reasons: "something else")) }.not_to raise_error
    expect { propose(evidence.manifest(reasons: "validation"), "q") }.not_to raise_error
  end

  it "still refuses a manifest whose candidates differ from the evidence" do
    manifest = JSON.parse(JSON.generate(evidence.manifest))
    manifest["candidates"][0]["status"] = "killed"
    manifest["accepted"] = []
    expect { propose(manifest) }.to raise_error(Saboteur::ConfigError, "baseline execution evidence differs")
  end
end
