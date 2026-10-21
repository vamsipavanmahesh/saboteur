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

  def run_returning(evidence)
    report = instance_double(Saboteur::Report, run_evidence: evidence, results: [])
    allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
  end

  def baseline_file
    manifest = Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")
    path = File.join(@root, "baseline.json")
    File.write(path, JSON.generate(manifest))
    path
  end

  it "validates a run only when it claims complete as exactly true" do
    path = baseline_file
    [false, nil, "true", 1].each do |claim|
      run_returning(document.merge("complete" => claim, "omissions" => [{}]))
      expect { workflow.check(path: path) }.not_to raise_error, claim.inspect
    end
  end

  it "publishes a proposal only from a run that claims proposable as exactly true" do
    ["true", 1, nil, false].each do |claim|
      run_returning(document.merge("proposable" => claim))
      expect { workflow.propose(proposal: File.join(@root, "p.json"), destination: File.join(@root, "b.json")) }
        .to raise_error(Saboteur::Error, "baseline proposal needs a proposable run"), claim.inspect
    end
  end

  it "prints every blocking issue, one per line, before the refusal sentence" do
    err = StringIO.new
    flow = described_class.new(config: config, err: err)
    blocked = document.merge("proposable" => false, "issues" => %w[inputs_unverified empty_candidates],
                             "blockers" => %w[inputs_unverified empty_candidates])
    run_returning(blocked)
    expect { flow.propose(proposal: File.join(@root, "p.json"), destination: File.join(@root, "b.json")) }
      .to raise_error(Saboteur::Error, "baseline proposal needs a proposable run")
    expect(err.string).to eq("saboteur: baseline proposal blocker: inputs_unverified\n" \
                             "saboteur: baseline proposal blocker: empty_candidates\n")
  end

  it "names the proposal first, then the destination, when guarding artifact paths" do
    proposal = File.join(@root, "p.rb")
    destination = File.join(@root, "d.rb")
    [[:propose, {}], [:accept, {}]].each do |action, extra|
      expect { workflow.public_send(action, proposal: proposal, destination: destination, **extra) }
        .to raise_error(Saboteur::ConfigError, "baseline artifact overlaps project input: #{proposal}")
      expect { workflow.public_send(action, proposal: File.join(@root, "p.json"), destination: destination, **extra) }
        .to raise_error(Saboteur::ConfigError, "baseline artifact overlaps project input: #{destination}")
    end
  end

  it "puts the cause in the baseline file message" do
    path = File.join(@root, "unreadable.json")
    File.write(path, "{}")
    # A stub, not chmod: a root-run CI container can read chmod-0 files.
    allow(File).to receive(:read).and_raise(Errno::EACCES)
    expect { workflow.check(path: path) }
      .to raise_error(Saboteur::ConfigError, /\Abaseline file: .*Permission denied/)
  end
end
