# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "hazard guard wiring (issue #102)" do
  let(:err) { StringIO.new }

  def engine(values = {})
    described_class.new(Saboteur::Config.new(values), err: err)
  end

  def rm_rf_subject
    subject_named("class K\n  def m\n    FileUtils.rm_rf(File.join(Dir.pwd, \"build\"))\n  end\nend\n", "K#m")
  end

  def edit_for(subject, text)
    at = subject.file_source.index(text)
    Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + text.size,
                                       replacement: "x")
  end

  def unguarded_hazard_digest(subject)
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    sources = Saboteur::Engine::Candidates.build_sources(Saboteur::Config.new)
    candidates = Saboteur::Engine::Candidates.new(sources, diagnostics, hazard_guard: nil)
    mutation, = candidates.for(subject).find { |m, _| m.operator == "literal_string" }
    mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
  end

  it "builds a guard from the config hazard list by default" do
    expect(engine.send(:hazard_guard)).to be_a(Saboteur::MutationSource::HazardGuard)
  end

  it "builds the guard from a custom hazard list" do
    guard = engine("hazard" => ["Deploys.destroy_everything"]).send(:hazard_guard)
    custom = subjects_in("class K\n  def m\n    Deploys.destroy_everything(\"prod\")\n  end\nend\n").first
    mutations = Saboteur::MutationSource::Builtin.new.mutations_for(custom)
    _kept, suppressed = guard.partition(mutations.map { |m| [m, nil] }, custom)
    expect(suppressed.map(&:first).map(&:operator)).to include("literal_string")
    standard = rm_rf_subject
    rm_mutations = Saboteur::MutationSource::Builtin.new.mutations_for(standard)
    kept, = guard.partition(rm_mutations.map { |m| [m, nil] }, standard)
    expect(kept.map(&:first).map(&:operator)).to include("literal_string")
  end

  it "disables the guard only with allow_hazardous" do
    expect(engine("allow_hazardous" => true).send(:hazard_guard)).to be_nil
  end

  # An old report, or one written under --allow-hazardous, can name a
  # hazardous digest; replaying it without the opt-in must be refused.
  it "refuses to replay a hazardous digest: the engine wires the guard into replay" do
    subject = rm_rf_subject
    digest = unguarded_hazard_digest(subject)
    replay_engine = described_class.new(Saboteur::Config.new, err: err, digest: digest)
    expect { replay_engine.send(:replay_subject, [subject], nil) }
      .to raise_error(Saboteur::ConfigError, /not found/)
  end

  it "resolves the same hazardous digest once replay runs with allow_hazardous" do
    subject = rm_rf_subject
    digest = unguarded_hazard_digest(subject)
    replay_engine = described_class.new(Saboteur::Config.new({ "allow_hazardous" => true }), err: err, digest: digest)
    selected, scope = replay_engine.send(:replay_subject, [subject], nil)
    expect([selected, scope]).to eq([[subject], nil])
    mutation, = replay_engine.instance_variable_get(:@replay_candidate).first
    expect(mutation.operator).to eq("literal_string")
  end

  it "checks the canary after each subject with the most recent mutant's digest" do
    subject = rm_rf_subject
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit_for(subject, "build")])
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "x")
    digest = mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    canary = instance_double(Saboteur::Engine::Canary)
    allow(Saboteur::Engine::Canary).to receive(:new).and_return(canary)
    expect(canary).to receive(:check!).with(subject:, digest:)
    engine.send(:canary_check).call(subject, [result])
  end

  it "prefers the last non-reused result and tolerates an empty result list" do
    subject = rm_rf_subject
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit_for(subject, "build")])
    fresh = Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "x")
    reused = Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "x",
                                        reused: true)
    digest = mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    canary = instance_double(Saboteur::Engine::Canary)
    allow(Saboteur::Engine::Canary).to receive(:new).and_return(canary)
    check = engine.send(:canary_check)
    expect(canary).to receive(:check!).with(subject:, digest:)
    check.call(subject, [fresh, reused])
    expect(canary).to receive(:check!).with(subject:, digest: nil)
    check.call(subject, [])
  end

  it "snapshots the tree excluding the configured cache directory" do
    canary = instance_double(Saboteur::Engine::Canary, check!: nil)
    allow(Saboteur::Engine::Canary).to receive(:new).and_return(canary)
    engine.send(:canary_check).call(Struct.new(:id).new("S#m"), [])
    expect(Saboteur::Engine::Canary).to have_received(:new).with(anything, cache_dir: ".saboteur")
  end

  it "flows the suppression count into the report" do
    e = engine
    subject = rm_rf_subject
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit_for(subject, "build")])
    e.instance_variable_get(:@diagnostics).record_hazard_suppression(subject, mutation)
    report = e.send(:build_report, [], [], nil, e.send(:monotonic))
    expect(report.hazard_suppressions).to eq(1)
  end

  it "attributes each result's own mutation when picking the canary digest" do
    subject = rm_rf_subject
    m1 = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                edits: [edit_for(subject, "build")])
    m2 = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                edits: [edit_for(subject, "rm_rf")])
    fresh = Saboteur::MutantResult.new(subject:, mutation: m1, status: :killed, mutated_source: "x")
    reused = Saboteur::MutantResult.new(subject:, mutation: m2, status: :killed, mutated_source: "x",
                                        reused: true)
    d1 = m1.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    d2 = m2.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    expect(d1).not_to eq(d2)
    canary = instance_double(Saboteur::Engine::Canary)
    allow(Saboteur::Engine::Canary).to receive(:new).and_return(canary)
    check = engine.send(:canary_check)
    expect(canary).to receive(:check!).with(subject:, digest: d1)
    check.call(subject, [fresh, reused])
    expect(canary).to receive(:check!).with(subject:, digest: d2)
    check.call(subject, [reused])
  end

  it "picks the most recent result for the canary digest, never the oldest" do
    subject = rm_rf_subject
    m1 = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                edits: [edit_for(subject, "build")])
    m2 = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                edits: [edit_for(subject, "rm_rf")])
    d2 = m2.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    fresh1 = Saboteur::MutantResult.new(subject:, mutation: m1, status: :killed, mutated_source: "x")
    fresh2 = Saboteur::MutantResult.new(subject:, mutation: m2, status: :killed, mutated_source: "x")
    reused1 = Saboteur::MutantResult.new(subject:, mutation: m1, status: :killed, mutated_source: "x",
                                         reused: true)
    reused2 = Saboteur::MutantResult.new(subject:, mutation: m2, status: :killed, mutated_source: "x",
                                         reused: true)
    canary = instance_double(Saboteur::Engine::Canary)
    allow(Saboteur::Engine::Canary).to receive(:new).and_return(canary)
    check = engine.send(:canary_check)
    expect(canary).to receive(:check!).with(subject:, digest: d2)
    check.call(subject, [fresh1, fresh2])
    expect(canary).to receive(:check!).with(subject:, digest: d2)
    check.call(subject, [reused1, reused2])
  end
end
