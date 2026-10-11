# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Diagnostics do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err) }

  it "collects warnings and counts invalid mutations" do
    diagnostics.warn("one")
    2.times { diagnostics.count_invalid_mutation }
    expect([diagnostics.warnings, diagnostics.invalid_mutations]).to eq([["one"], 2])
  end

  it "prints one mark per executed mutant" do
    %i[killed survived timeout error].each { |status| diagnostics.progress(instance_double(Saboteur::MutantResult, status:)) }
    expect(err.string).to eq(".STE")
  end

  it "prefixes messages for the user" do
    diagnostics.inform("building")
    expect(err.string).to eq("saboteur: building\n")
  end
end

RSpec.describe Saboteur::Engine::Diagnostics, "progress heartbeat" do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err) }

  it "prints elapsed time about every interval while the block runs" do
    diagnostics.with_progress_heartbeat("long phase", interval: 0.01) { sleep 0.05 }
    expect(err.string).to match(/long phase: 0 s elapsed/)
    expect(err.string.lines.size).to be >= 2
  end

  it "stops the heartbeat when the block raises" do
    expect do
      diagnostics.with_progress_heartbeat("long phase", interval: 0.01) { raise "boom" }
    end.to raise_error("boom")
    lines = err.string.lines.size
    sleep 0.05
    expect(err.string.lines.size).to eq(lines)
  end
end
