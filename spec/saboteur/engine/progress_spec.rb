# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Diagnostics, "progress summary" do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err) }

  def at_clock(started, now)
    diagnostics.instance_variable_set(:@progress_started, started)
    allow(Process).to receive(:clock_gettime).and_return(now)
  end

  describe "#progress_summary" do
    before { diagnostics.start_progress(7) }

    it "adds the percentage and a whole-minute-and-second estimate" do
      at_clock(100.0, 150.0)
      expect(diagnostics.progress_summary(2)).to eq("2/7 (28%) eta 2m05s")
    end

    it "shows the estimate when exactly one mutant is left, and none when none is" do
      at_clock(0.0, 10.0)
      expect(diagnostics.progress_summary(6)).to eq("6/7 (85%) eta 0m02s")
      at_clock(0.0, 10.0)
      expect(diagnostics.progress_summary(7)).to eq("7/7 (100%)")
    end

    it "shows no estimate before the first mutant or past the total" do
      expect(diagnostics.progress_summary(0)).to eq("0/7 (0%)")
      expect(diagnostics.progress_summary(8)).to eq("8/7 (114%)")
    end

    it "rolls seconds into minutes at sixty" do
      at_clock(0.0, 59.0)
      expect(diagnostics.progress_summary(1)).to eq("1/7 (14%) eta 5m54s")
      at_clock(0.0, 10.0)
      expect(diagnostics.progress_summary(1)).to eq("1/7 (14%) eta 1m00s")
    end

    it "prints only done/total without an announced total" do
      bare = described_class.new(StringIO.new)
      expect(bare.progress_summary(3)).to eq("3/")
    end
  end
end
