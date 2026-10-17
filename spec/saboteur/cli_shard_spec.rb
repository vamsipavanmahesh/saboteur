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
end
