# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "saboteur/baseline/workflow"

RSpec.describe Saboteur::Baseline::Workflow do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end
  let(:config) { Saboteur::Config.new({}, root: @root) }
  let(:workflow) { described_class.new(config: config) }
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

  def stub_run
    report = instance_double(Saboteur::Report, run_evidence: document)
    engine = instance_double(Saboteur::Engine, call: report)
    allow(Saboteur::Engine).to receive(:new).and_return(engine)
  end

  def review(path)
    record = JSON.parse(File.read(path))
    record.fetch("document").fetch("accepted").each { |entry| entry["reason"] = "reviewed" }
    File.write(path, JSON.generate(record))
    record
  end

  it "proposes bound immutable producer evidence and accepts it only once" do
    stub_run
    proposal = File.join(@root, "proposal.json")
    destination = File.join(@root, "baseline.json")
    value = workflow.propose(proposal: proposal, destination: destination)
    expect(value).to eq("state" => "proposal", "proposal" => proposal, "destination" => destination, "survivors" => 1)
    record = review(proposal)
    expect(record.fetch("execution")).to eq(JSON.parse(JSON.generate(document)))
    expect(workflow.accept(proposal: proposal, destination: destination))
      .to eq("state" => "accepted", "destination" => destination)
    expect { workflow.accept(proposal: proposal, destination: destination) }.to raise_error(Saboteur::ConfigError)
  end

  it "rejects stale inputs or editable execution history before publishing" do
    stub_run
    proposal = File.join(@root, "proposal.json")
    destination = File.join(@root, "baseline.json")
    workflow.propose(proposal: proposal, destination: destination)
    record = review(proposal)
    record.fetch("execution")["generation_events"] = []
    record.fetch("execution")["issues"] = ["edited"]
    File.write(proposal, JSON.generate(record))
    expect { workflow.accept(proposal: proposal, destination: destination) }.to raise_error(Saboteur::ConfigError)
    record.fetch("execution")["issues"] = []
    File.write(proposal, JSON.generate(record))
    File.write(File.join(@root, "probe.rb"), "changed")
    expect { workflow.accept(proposal: proposal, destination: destination) }
      .to raise_error(Saboteur::ConfigError, /inputs/)
    expect(File.exist?(destination)).to be(false)
  end

  it "refuses nonfresh configuration and artifact paths that overlap present or future inputs" do
    [{ "since" => "main" }, { "incremental" => true }, { "threshold" => 90 }].each do |settings|
      expect { described_class.new(config: Saboteur::Config.new(settings, root: @root)) }
        .to raise_error(Saboteur::ConfigError)
    end
    %w[lib/a.rb config/database.yml Gemfile spec/fixtures/data.json].each do |path|
      expect { workflow.propose(proposal: File.join(@root, path), destination: File.join(@root, "b.json")) }
        .to raise_error(Saboteur::ConfigError, /overlaps/)
    end
  end

  it "runs check fresh with the baseline file in the input fingerprint and returns review state" do
    manifest = Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")
    path = File.join(@root, "baseline.json")
    File.write(path, JSON.generate(manifest))
    stub_run
    expect(workflow.check(path: path).fetch("state")).to eq("clean")
    expect(Saboteur::Engine).to have_received(:new).with(config, err: $stderr, capture_evidence: true,
                                                                 evidence_files: [path])
  end
end
