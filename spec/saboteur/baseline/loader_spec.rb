# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Baseline::Loader do
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

  def write(manifest)
    path = File.join(@root, "baseline.json")
    File.write(path, JSON.generate(manifest))
    path
  end

  it "loads a current manifest, restoring the proposability tier for validation" do
    path = write(Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known"))
    manifest, digest = described_class.call(path)
    expect(manifest.candidates).not_to be_empty
    expect(digest).to match(/\A[0-9a-f]{64}\z/)
  end

  it "loads a legacy manifest without the proposable key, deriving the tier from the strict flag" do
    manifest = Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")
    manifest.fetch("metadata").delete("proposable")
    value, = described_class.call(write(manifest))
    expect(value.to_h.fetch("metadata")).not_to have_key("proposable")
  end

  it "loads a proposable manifest whose issues are soft gaps, listed in the metadata" do
    gap = "subject_skipped:probe.rb:Probe#other:no_tests"
    gapped = document.merge("complete" => false, "issues" => [gap], "gaps" => [gap], "blockers" => [])
    manifest = Saboteur::Baseline::Evidence.new(gapped).manifest(reasons: "known")
    value, = described_class.call(write(manifest))
    expect(value.to_h.fetch("metadata").fetch("issues")).to eq([gap])
  end

  it "rejects a tampered tier split that no longer sums to the issues list" do
    tampered = document.merge("blockers" => ["missing_result:x"], "issues" => [], "gaps" => [])
    expect { Saboteur::Baseline::Evidence.new(tampered) }
      .to raise_error(Saboteur::ConfigError, /completeness tiers disagree/)
  end

  it "validates the restored evidence: a manifest whose runtime no longer matches its snapshot is refused" do
    manifest = JSON.parse(JSON.generate(Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")))
    manifest.fetch("metadata").fetch("runtime")["version"] = "0.0.0-tampered"
    expect { described_class.call(write(manifest)) }
      .to raise_error(Saboteur::ConfigError, /baseline snapshot settings mismatch/)
  end

  it "names a missing baseline file and how to create it" do
    path = File.join(@root, "absent.json")
    expect { described_class.call(path) }.to raise_error(
      Saboteur::ConfigError,
      "baseline file #{path} does not exist; create it with saboteur baseline propose --baseline #{path}"
    )
  end

  it "wraps unreadable or malformed files as a baseline file error" do
    bad = File.join(@root, "bad.json")
    File.write(bad, "{not json")
    expect { described_class.call(bad) }.to raise_error(Saboteur::ConfigError, /\Abaseline file: /)
    expect { described_class.call(@root) }.to raise_error(Saboteur::ConfigError, /\Abaseline file: .*directory/i)
  end
end
