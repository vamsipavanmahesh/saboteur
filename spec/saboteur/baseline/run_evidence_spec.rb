# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "saboteur/baseline/run_evidence"

RSpec.describe Saboteur::Baseline::RunEvidence do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      example.run
    end
  end
  let(:config) { Saboteur::Config.new({}, root: @root) }
  let(:evidence) do
    subject
    described_class.new(config: config)
  end
  let(:subject) do
    path = File.join(@root, "probe.rb")
    File.write(path, "class Probe; def value; 1; end; end")
    Saboteur::SubjectFinder.new.call(path).subjects.first
  end
  let(:mutation) do
    start = subject.file_source.index("1")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: start, end_byte: start + 1,
                                              replacement: "0")
    Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "number", edits: [edit])
  end
  let(:result) do
    Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :survived,
                               mutated_source: subject.apply(mutation.edits))
  end

  def finish(events: [], omissions: [], results: [result], stable_suite: true)
    evidence.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
    evidence.finish(results: results, stable_suite: stable_suite, skipped_subjects: {},
                    generation_events: events, omissions: omissions)
  end

  it "reconciles one fresh outcome with the pre-execution plan and immutable metadata" do
    captured = finish
    expect(captured.fetch("complete")).to be(true)
    expect(captured.fetch("issues")).to be_empty
    expect(captured.fetch("candidates").first.fetch("id")).to match(/\A[0-9a-f]{64}\z/)
    expect(captured.fetch("compatibility").fetch("config")).not_to have_key("json_report")
    expect(captured).to be_frozen
    expect(captured.fetch("candidates")).to be_frozen
  end

  it "binds versioned effective operators and rejects a 0.5.0 baseline without auto-acceptance" do
    current = JSON.parse(JSON.generate(finish))
    policy = current.fetch("compatibility").fetch("config").fetch("operator_policy")
    expect(policy).to eq(config.operator_policy)
    previous = Marshal.load(Marshal.dump(current.fetch("compatibility")))
    previous["config"].delete("operator_policy")
    previous["config"].delete("exclude_operators")
    comparison = Saboteur::Baseline::Comparison.new(
      baseline: { "compatibility" => previous, "accepted" => [], "candidates" => [] }, current: current
    )
    expect(comparison.state).to eq("incompatible")
    expect(comparison.exit_code).to eq(2)
    expect(comparison.issues.join).to include("re-propose with baseline propose")
  end

  it "normalizes symlinked checkout paths for subjects, edits and missing discovery files" do
    subject
    Dir.mktmpdir do |parent|
      link = File.join(parent, "checkout")
      File.symlink(@root, link)
      linked = Saboteur::SubjectFinder.new.call(File.join(link, "probe.rb")).subjects.first
      linked_mutation = mutation.with(subject_id: linked.id)
      fresh = described_class.new(config: Saboteur::Config.new({}, root: link))
      fresh.plan([linked], [[[linked_mutation, subject.apply(mutation.edits)]]])
      linked_result = Saboteur::MutantResult.new(subject: linked, mutation: linked_mutation,
                                                 status: :survived, mutated_source: subject.apply(mutation.edits))
      failure = Saboteur::Engine::Diagnostics::DiscoveryFailure.new(
        file: File.join(link, "missing.rb"), reason: "invalid_file_syntax"
      )
      captured = fresh.finish(results: [linked_result], stable_suite: true, skipped_subjects: {},
                              generation_events: [], omissions: [], discovery_failures: [failure])
      expect(captured.fetch("subjects")).to eq([["probe.rb", "Probe#value"]])
      expect(captured.fetch("planned").first.fetch("identity")[1]).to eq("probe.rb")
      expect(captured.fetch("issues")).to eq(["generation:discovery:invalid_file_syntax:missing.rb"])
    end
  end

  it "retains and blocks typed discovery failure independently of valid generated work" do
    evidence.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
    failure = Saboteur::Engine::Diagnostics::DiscoveryFailure.new(
      file: File.join(@root, "broken.rb"), reason: "invalid_file_syntax"
    )
    captured = evidence.finish(results: [result], stable_suite: true, skipped_subjects: {},
                               generation_events: [], omissions: [], discovery_failures: [failure])
    expect(captured.fetch("complete")).to be(false)
    expect(captured.fetch("issues")).to eq(["generation:discovery:invalid_file_syntax:broken.rb"])
    expect(captured.fetch("discovery_failures")).to eq([
                                                         { "file" => failure.file, "reason" => "invalid_file_syntax" }
                                                       ])
  end

  it "copies the subject list before caller-owned subject names can change" do
    name = +"Probe#value"
    allow(subject).to receive(:id).and_return(name)
    evidence.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
    name.replace("changed")
    expect(evidence.instance_variable_get(:@subjects)).to eq([["probe.rb", "Probe#value"]])
    expect(evidence.instance_variable_get(:@planned).first.fetch("identity")[2]).to eq("Probe#value")
    name.replace("Probe#value")
    captured = evidence.finish(results: [result], stable_suite: true, skipped_subjects: {},
                               generation_events: [], omissions: [])
    expect(captured.fetch("subjects")).to eq([["probe.rb", "Probe#value"]])
    expect(captured.fetch("planned").first.fetch("identity")[2]).to eq("Probe#value")
  end

  it "retains a first invalid event even when the same text later records duplicate" do
    events = %w[invalid_syntax duplicate].map do |reason|
      Saboteur::Engine::Diagnostics::GenerationEvent.new(file: subject.file, subject: subject.id,
                                                         source: "builtin", operator: "bad", reason: reason)
    end
    captured = finish(events: events)
    expect(captured.fetch("complete")).to be(false)
    expect(captured.fetch("issues")).to include("generation:invalid_syntax:Probe#value:bad")
    expect(captured.fetch("generation_events").map do |event|
      event.fetch("reason")
    end).to eq(%w[invalid_syntax duplicate])
  end

  it "blocks empty generation and invalid subject syntax rather than safe dropping them" do
    %w[empty_generation invalid_subject_syntax].each do |reason|
      fresh = described_class.new(config: config)
      fresh.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
      event = Saboteur::Engine::Diagnostics::GenerationEvent.new(
        file: subject.file, subject: subject.id, source: "builtin", operator: nil, reason: reason
      )
      captured = fresh.finish(results: [result], stable_suite: true, skipped_subjects: {},
                              generation_events: [event], omissions: [])
      expect(captured.fetch("complete")).to be(false)
      expect(captured.fetch("issues")).to include("generation:#{reason}:Probe#value")
    end
  end

  it "blocks missing results, cap omissions, skips, reused verdicts and unstable suite evidence" do
    omitted = Saboteur::Engine::Diagnostics::Omission.new(subject: subject.id, count: 2, limit: 1)
    captured = finish(omissions: [omitted], results: [], stable_suite: false)
    expect(captured.fetch("issues")).to include("unchanged_suite_incomplete", "omitted:Probe#value:2")
    expect(captured.fetch("issues").any? { |issue| issue.start_with?("missing_result:") }).to be(true)
  end

  it "blocks a reused verdict even when the terminal status is survived" do
    reused = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :survived,
                                        mutated_source: subject.apply(mutation.edits), reused: true)
    expect(finish(results: [reused]).fetch("issues")).to include("generation:reused:Probe#value")
  end

  it "blocks duplicate terminal outcomes rather than counting one verdict twice" do
    captured = finish(results: [result, result])
    expect(captured.fetch("complete")).to be(false)
    expect(captured.fetch("issues")).to include("duplicate_results")
  end

  it "blocks errors and skipped outcomes rather than treating missing evidence as detection" do
    %i[error resource_limit skipped].each do |status|
      other = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: status,
                                         mutated_source: subject.apply(mutation.edits))
      fresh = described_class.new(config: config)
      fresh.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
      captured = fresh.finish(results: [other], stable_suite: true, skipped_subjects: {},
                              generation_events: [], omissions: [])
      expect(captured.fetch("complete")).to be(false)
    end
  end

  it "rejects missing, repeated and dimensionally inconsistent plans" do
    expect do
      evidence.finish(results: [], stable_suite: true, skipped_subjects: {}, generation_events: [], omissions: [])
    end.to raise_error(Saboteur::ConfigError, "baseline plan missing")
    expect { evidence.plan([subject], []) }.to raise_error(Saboteur::ConfigError,
                                                           "baseline candidate lists differ from subjects")
    evidence.plan([subject], [[]])
    expect { evidence.plan([subject], [[]]) }.to raise_error(Saboteur::ConfigError, "baseline plan already recorded")
  end

  it "pins compatibility, planned identity and outcome fields without hiding report destinations" do
    captured = finish
    metadata = captured.fetch("compatibility")
    expect(metadata.keys).to contain_exactly("generator", "runtime", "config", "scope")
    expect(metadata.fetch("generator")).to eq("saboteur" => Saboteur::VERSION, "sources" => ["builtin"],
                                              "plugins" => [])
    expect(metadata.fetch("runtime")).to eq(Saboteur::Engine::RunFingerprint.canonical_value(
                                              Saboteur::Engine::RunFingerprint.runtime_identity
                                            ))
    expect(metadata.fetch("config")).to eq(Saboteur::Engine::RunFingerprint.canonical_value(
                                             config.selection_settings.except("cache_dir", "json_report", "html_report",
                                                                              "score_history", "resume", "palette")
                                           ))
    expect(metadata.fetch("scope")).to eq("include" => config["include"], "exclude" => config["exclude"],
                                          "subjects" => config["subjects"])
    identity = Saboteur::Baseline::Identity.new(subject: subject, mutation: mutation, root: @root).entry
    expect(captured.fetch("subjects")).to eq([["probe.rb", "Probe#value"]])
    expect(captured.fetch("planned")).to eq([identity])
    expect(captured.fetch("candidates")).to eq([identity.merge("status" => "survived", "kill_cause" => nil)])
    expect(captured.fetch("snapshot").keys).to contain_exactly("format_version", "digest", "inventory",
                                                               "settings_digest", "runtime_digest",
                                                               "complete", "issues")
    expect(captured.fetch("generation_events")).to be_empty
    expect(captured.fetch("omissions")).to be_empty
  end

  it "tracks an explicit external evidence input and detects its edits" do
    subject
    Dir.mktmpdir do |outside|
      path = File.join(outside, "data.txt")
      File.write(path, "before")
      fresh = described_class.new(config: config, extra_files: [path])
      fresh.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
      File.write(path, "after")
      captured = fresh.finish(results: [result], stable_suite: true, skipped_subjects: {},
                              generation_events: [], omissions: [])
      expect(captured.fetch("issues")).to include("inputs_unverified")
    end
  end

  it "rejects a selected subject outside the checkout" do
    outside = subjects_in("class Outside; def value; 1; end; end").first
    expect { evidence.plan([outside], [[]]) }.to raise_error(Saboteur::ConfigError,
                                                             "baseline subject outside project root")
  end

  it "blocks changed subject context even when the local mutation identity remains equal" do
    evidence.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
    allow(subject).to receive(:source).and_return("changed subject context")
    captured = evidence.finish(results: [result], stable_suite: true, skipped_subjects: {},
                               generation_events: [], omissions: [])
    id = captured.fetch("planned").first.fetch("id")
    expect(captured.fetch("issues")).to include("generation:changed_context:#{id}")
    expect(captured.fetch("complete")).to be(false)
  end

  it "pins the external generator input hash as compatibility, not ordinary Ruby files" do
    subject
    plugin = File.join(@root, "plugin.rb")
    File.write(plugin, "class Plugin; end")
    custom_config = Saboteur::Config.new({ "sources" => ["plugin.rb:Plugin"] }, root: @root)
    fresh = described_class.new(config: custom_config)
    fresh.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
    captured = fresh.finish(results: [result], stable_suite: true, skipped_subjects: {},
                            generation_events: [], omissions: [])
    expected = { "path" => "plugin.rb", "kind" => "source_plugin", "state" => "present",
                 "sha256" => Digest::SHA256.file(plugin).hexdigest, "required" => true }
    expect(captured.fetch("compatibility").fetch("generator").fetch("plugins")).to eq([expected])
  end

  it "reports an unexpected result without requiring it to have a planned context" do
    evidence.plan([subject], [[]])
    captured = evidence.finish(results: [result], stable_suite: true, skipped_subjects: {},
                               generation_events: [], omissions: [])
    expect(captured.fetch("issues").any? { |issue| issue.start_with?("unexpected_result:") }).to be(true)
  end

  it "blocks input changes after capture" do
    evidence
    File.write(File.join(@root, "new.rb"), "changed")
    expect(finish.fetch("issues")).to include("inputs_unverified")
  end
  it "retains inline audit scope and refuses completeness even with every selected verdict present" do
    evidence.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
    row = { file: subject.file, line: 1, subject: subject.id, operator: "number", reason: "elsewhere", digest: "abc" }
    captured = evidence.finish(results: [result], stable_suite: true, skipped_subjects: {},
                               generation_events: [], omissions: [], inline_suppressions: [row])
    expect(captured.fetch("complete")).to be(false)
    expect(captured.fetch("issues")).to eq(["generation:inline_suppressed:Probe#value:abc"])
    expect(captured.fetch("inline_suppressions")).to eq([row.transform_keys(&:to_s).merge("file" => "probe.rb")])
    expect(captured.fetch("inline_suppressions").first).to be_frozen
    row[:reason] = "changed"
    expect(captured.fetch("inline_suppressions").first.fetch("reason")).to eq("elsewhere")
  end
end
