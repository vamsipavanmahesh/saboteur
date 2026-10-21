# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require_relative "../../support/report_helpers"

# Pins the --flaky-check option surface (#476): the accepted modes, the
# rejection of anything else, and the help text.
RSpec.describe Saboteur::CLI, "--flaky-check option" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  before do
    engine = engine_double(guessed_tests: nil, call: report_of(result_for(:killed)))
    allow(Saboteur::Engine).to receive(:new).and_return(engine)
    allow(Saboteur::Reporter::Terminal).to receive(:new) { |*_a, **_kw| instance_double(Saboteur::Reporter::Terminal, call: nil) }
  end

  def run_with(*flags)
    described_class.new(["run", *flags], out: out, err: err).call
  end

  it "accepts off, survivors and decisive" do
    %w[off survivors decisive].each do |mode|
      expect(run_with("--flaky-check", mode)).to eq(0), mode
    end
  end

  it "rejects any other mode as a usage error" do
    expect(run_with("--flaky-check", "sometimes")).to eq(2)
    expect(err.string).to include("--flaky-check")
  end

  it "documents the confirmation rerun in the run help" do
    expect(described_class.new(%w[help run], out: out, err: err).call).to eq(0)
    expect(out.string).to include("--flaky-check MODE",
                                  "Confirm a fresh verdict (survivors, decisive) with one reordered rerun")
  end
end
