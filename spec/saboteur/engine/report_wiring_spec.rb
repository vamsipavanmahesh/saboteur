# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "report wiring" do
  it "flows the run's discovery failures into the report" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    engine.instance_variable_get(:@diagnostics).record_discovery_failure("/r/a.rb", reason: "unreadable")
    report = engine.send(:build_report, [], [], nil, engine.send(:monotonic))
    expect(report.discovery_failures.map(&:reason)).to eq(["unreadable"])
  end

  it "flows the selected shard into the report" do
    shard = Saboteur::Engine::Shard.parse("1/2")
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    engine.instance_variable_set(:@shard, shard)
    report = engine.send(:build_report, [], [], nil, engine.send(:monotonic))
    expect(report.shard).to be(shard)
  end

  it "labels the reuse mechanism as the flag passed, and never labels a replay" do
    engine = described_class.new(Saboteur::Config.new({ "incremental" => true }), err: StringIO.new)
    expect(engine.send(:reuse_label)).to eq("--incremental")

    resumed = described_class.new(Saboteur::Config.new({ "resume" => "state" }), err: StringIO.new)
    expect(resumed.send(:reuse_label)).to eq("--resume")

    plain = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    expect(plain.send(:reuse_label)).to be_nil

    # A replay recomputes one mutant fresh: even with --incremental typed,
    # it reuses nothing, so the note must not name a flag.
    engine.instance_variable_set(:@replay, Object.new)
    expect(engine.send(:reuse_label)).to be_nil
  end

  it "flows the reuse label into the report" do
    engine = described_class.new(Saboteur::Config.new({ "incremental" => true }), err: StringIO.new)
    report = engine.send(:build_report, [], [], nil, engine.send(:monotonic))
    expect(report.reuse_label).to eq("--incremental")

    resumed = described_class.new(Saboteur::Config.new({ "resume" => "state" }), err: StringIO.new)
    report = resumed.send(:build_report, [], [], nil, resumed.send(:monotonic))
    expect(report.reuse_label).to eq("--resume")

    plain = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    report = plain.send(:build_report, [], [], nil, plain.send(:monotonic))
    expect(report.reuse_label).to be_nil

    engine.instance_variable_set(:@replay, Object.new)
    report = engine.send(:build_report, [], [], nil, engine.send(:monotonic))
    expect(report.reuse_label).to be_nil
  end

  it "flows the --since ref into the report, so reporters can echo the scope" do
    engine = described_class.new(Saboteur::Config.new({ "since" => "HEAD~1" }), err: StringIO.new)
    report = engine.send(:build_report, [], [], nil, engine.send(:monotonic))
    expect(report.since).to eq("HEAD~1")
  end

  it "flows the configured --test-command into the report (#641)" do
    config = Saboteur::Config.new({ "test_command" => "bin/rails test" })
    engine = described_class.new(config, err: StringIO.new)
    report = engine.send(:build_report, [], [], nil, engine.send(:monotonic))
    expect(report.test_command).to eq("bin/rails test")
  end

  it "hands the engine root to candidate selection so skip announcements stay relative (#627)" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    subject = instance_double(Saboteur::Subject)
    map = instance_double(Saboteur::Selection::CoverageMap)
    selection = instance_double(Saboteur::Engine::CandidateSelection,
                                skipped_subjects: {}, unscoped_digests: {})
    allow(selection).to receive(:for).with(subject, scope: nil).and_return([])
    expect(Saboteur::Engine::CandidateSelection).to receive(:new)
      .with(hash_including(root: engine.instance_variable_get(:@root)))
      .and_return(selection)
    engine.send(:candidate_lists, [subject], nil, map)
  end

  it "passes the diff scope through before applying the shard" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    subject = instance_double(Saboteur::Subject)
    scope = instance_double(Saboteur::Engine::DiffScope)
    map = instance_double(Saboteur::Selection::CoverageMap)
    selection = instance_double(Saboteur::Engine::CandidateSelection,
                                skipped_subjects: {}, unscoped_digests: {})
    allow(Saboteur::Engine::CandidateSelection).to receive(:new).and_return(selection)
    expect(selection).to receive(:for).with(subject, scope: scope).and_return([])
    expect(engine.send(:candidate_lists, [subject], scope, map)).to eq([[]])
  end

  it "applies the parsed shard to the planned lists" do
    config = Saboteur::Config.new({ "shard" => "1/2" })
    engine = described_class.new(config, err: StringIO.new)
    subject = instance_double(Saboteur::Subject)
    map = instance_double(Saboteur::Selection::CoverageMap)
    planned = [instance_double(Saboteur::MutationSource::Mutation)]
    selection = instance_double(Saboteur::Engine::CandidateSelection,
                                skipped_subjects: {}, unscoped_digests: {})
    shard = instance_double(Saboteur::Engine::Shard)
    allow(Saboteur::Engine::CandidateSelection).to receive(:new).and_return(selection)
    allow(selection).to receive(:for).with(subject, scope: nil).and_return(planned)
    allow(Saboteur::Engine::Shard).to receive(:parse).with("1/2").and_return(shard)
    expect(shard).to receive(:select).with([subject], [planned]).and_return([[]])
    expect(engine.send(:candidate_lists, [subject], nil, map)).to eq([[]])
  end

  it "flows the phase timings into the report" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    timings = Saboteur::PhaseTimings.new(baseline_seconds: 1.0, map_seconds: 2.0, map_cached: false,
                                         mutants_seconds: 3.0, jobs: 2)
    engine.instance_variable_set(:@phase_timings, timings)
    report = engine.send(:build_report, [], [], nil, engine.send(:monotonic))
    expect(report.phase_timings).to be(timings)
  end

  it "times the map fetch as the difference of two monotonic reads" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    store = Object.new
    def store.fetch(*) = :the_map
    reads = [10.0, 12.5]
    engine.define_singleton_method(:monotonic) { reads.shift }
    map, seconds = engine.send(:timed_map_fetch, store, [:files])
    expect([map, seconds]).to eq([:the_map, 2.5])
  end

  it "records the three phase splits and the job count for the speed footer" do
    engine = described_class.new(Saboteur::Config.new({ "jobs" => 3 }), err: StringIO.new)
    engine.instance_variable_set(:@baseline_elapsed, 4.25)
    reads = [20.0, 27.5]
    engine.define_singleton_method(:monotonic) { reads.shift }
    engine.define_singleton_method(:run_and_confirm) { |*| :results }
    engine.send(:run_and_confirm_timed, [], [], nil, nil, nil, map_cached: false, map_seconds: 6.5)
    expect(engine.instance_variable_get(:@phase_timings)).to eq(
      Saboteur::PhaseTimings.new(baseline_seconds: 4.25, map_seconds: 6.5, map_cached: false,
                                 mutants_seconds: 7.5, jobs: 3)
    )
  end

  it "reports zero baseline seconds when the baseline phase never timed itself" do
    engine = described_class.new(Saboteur::Config.new({ "jobs" => 1 }), err: StringIO.new)
    reads = [1.0, 2.0]
    engine.define_singleton_method(:monotonic) { reads.shift }
    engine.define_singleton_method(:run_and_confirm) { |*| :results }
    engine.send(:run_and_confirm_timed, [], [], nil, nil, nil, map_cached: true, map_seconds: 9.0)
    timings = engine.instance_variable_get(:@phase_timings)
    expect(timings.baseline_seconds).to eq(0.0)
    expect(timings.mutants_seconds).to eq(1.0)
  end
end
