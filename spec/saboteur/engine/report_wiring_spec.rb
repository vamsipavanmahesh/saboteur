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
end
