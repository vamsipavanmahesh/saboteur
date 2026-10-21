# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# Pins that Engine#call never loads the ignore file in replay mode: the
# replay verdict must not depend on the current ignore list.
RSpec.describe Saboteur::Engine, "#call replay pins" do
  before { allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!) }

  def engine_with(values, **kwargs)
    config = Saboteur::Config.new(values, root: Dir.pwd)
    described_class.new(config, err: StringIO.new, **kwargs)
  end

  it "uses an empty ignore list in replay mode instead of loading the ignore file" do
    engine = engine_with({ "tests" => ["spec/a_spec.rb"] }, digest: "0123456789abcdef")
    allow(engine).to receive(:preflight!)
    allow(engine).to receive(:ensure_artifacts_self_ignored)
    allow(engine).to receive(:start_budget_clock)
    allow(engine).to receive(:select_tests)
    allow(engine).to receive(:announce_operators)
    allow(engine).to receive(:warn_custom_map)
    allow(engine).to receive(:run_pipeline)
    allow(Saboteur::IgnoreList).to receive(:load).and_call_original

    engine.call

    expect(Saboteur::IgnoreList).not_to have_received(:load)
    expect(engine).to have_received(:run_pipeline) do |ignore_list, _started|
      expect(ignore_list.entries).to eq([])
    end
  end
end
