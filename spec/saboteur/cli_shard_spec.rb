# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "saboteur run --shard" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    Saboteur::CLI.new(argv, out:, err:)
  end

  it "rejects malformed and out-of-range shard pairs as usage errors" do
    ["0/2", "1/1", "3/2", "one/two"].each do |value|
      expect(cli("run", "--shard", value).call).to eq(2), value
      expect(err.string).to include("shard must be k/n")
      err.truncate(0)
    end
  end

  it "keeps replay and shard selection mutually exclusive" do
    expect(cli("run", "--id", "a" * 32, "--shard", "1/2").call).to eq(2)
    expect(err.string).to include("--id cannot be combined with --shard")
  end

  it "replays one mutant without a shard and never raises the shard error" do
    config = Saboteur::Config.new({ "json_report" => nil })
    allow(Saboteur::Config).to receive(:load).and_return(config)
    report = report_of(result_for(:killed))
    allow(Saboteur::Engine).to receive(:new).and_return(engine_double(call: report))
    expect(cli("run", "--id", "a" * 16).call).to eq(0)
    expect(err.string).not_to include("--id cannot be combined with --shard")
  end

  it "runs unsharded without parsing a shard" do
    config = Saboteur::Config.new({ "json_report" => nil })
    allow(Saboteur::Config).to receive(:load).and_return(config)
    report = report_of(result_for(:killed))
    allow(Saboteur::Engine).to receive(:new).and_return(engine_double(call: report))
    expect(cli("run").call).to eq(0)
    expect(err.string).not_to include("shard must be k/n")
  end

  it "documents the public flag and its argument" do
    expect(cli("help", "run").call).to eq(0)
    expect(out.string).to include("--shard K/N", "Run one of N deterministic candidate shards (for example 1/4)")
  end
end
