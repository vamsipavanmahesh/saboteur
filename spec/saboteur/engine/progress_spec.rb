# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Diagnostics, "progress" do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err) }
  let(:result) { Struct.new(:status).new(:killed) }

  it "prints a legend, dots, and a counter with percentage and eta every 50 mutants outside a terminal" do
    diagnostics.start_progress(100)
    50.times { diagnostics.progress(result) }
    diagnostics.finish_progress
    expect(err.string).to include("progress . killed  S survived", "50/100 (50%) eta")
  end

  it "prints dots only when no total was announced" do
    diagnostics.progress(result)
    expect(err.string).to eq(".")
  end

  it "rewrites one line with the counter on a terminal" do
    allow(err).to receive(:tty?).and_return(true)
    diagnostics.start_progress(4)
    2.times { diagnostics.progress(result) }
    diagnostics.finish_progress
    expect(err.string).to include("saboteur: 1/4 (25%)", "saboteur: 2/4 (50%) eta")
    expect(err.string).not_to include("progress .")
  end
end
