# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Pins that Engine#candidate_lists replays the recorded candidate
# without building the candidate list again.
RSpec.describe Saboteur::Engine, "#candidate_lists replay pins" do
  before { allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!) }

  it "returns the replay candidate and builds nothing in replay mode" do
    config = Saboteur::Config.new({}, root: Dir.pwd)
    engine = described_class.new(config, err: StringIO.new, digest: "0123456789abcdef")
    engine.instance_variable_set(:@replay_candidate, :recorded)
    allow(Saboteur::Engine::Candidates).to receive(:build)

    expect(engine.send(:candidate_lists, [], nil, nil)).to eq([:recorded])
    expect(Saboteur::Engine::Candidates).not_to have_received(:build)
  end
end
