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

  it "ends a partial line with a newline and removes the progress file" do
    diagnostics.start_progress(10)
    3.times { diagnostics.progress(result) }
    file = diagnostics.instance_variable_get(:@progress_file)
    before = err.string.dup
    diagnostics.finish_progress
    expect(err.string).to eq("#{before}\n")
    expect(file.path).to be_nil
    expect(diagnostics.instance_variable_get(:@progress_file)).to be_nil
  end

  it "adds no newline after a full line of marks, or when no progress was started" do
    diagnostics.start_progress(50)
    Saboteur::Engine::Diagnostics::LINE_WIDTH.times { diagnostics.progress(result) }
    before = err.string.dup
    diagnostics.finish_progress
    expect(err.string).to eq(before)
    diagnostics.finish_progress
    expect(err.string).to eq(before)
  end
end

RSpec.describe Saboteur::Engine::Diagnostics, "progress details" do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err) }
  let(:killed) { Struct.new(:status).new(:killed) }

  def at_clock(started, now)
    diagnostics.instance_variable_set(:@progress_started, started)
    allow(Process).to receive(:clock_gettime).and_return(now)
  end

  it "keeps its count in a binary, unbuffered file named for saboteur" do
    diagnostics.start_progress(5)
    file = diagnostics.instance_variable_get(:@progress_file)
    expect(File.basename(file.path)).to start_with("saboteur-progress")
    expect(file.sync).to be(true)
    expect(file.external_encoding).to eq(Encoding::BINARY)
  end

  it "prints a question mark for a status it has no mark for, and flushes after each mark" do
    allow(err).to receive(:flush).and_call_original
    diagnostics.start_progress(5)
    diagnostics.progress(Struct.new(:status).new(:mystery))
    expect(err.string).to end_with("?")
    expect(err).to have_received(:flush).at_least(:once)
  end

  it "prints marks, not carriage returns, when the output is not a terminal, and the counter every 50" do
    diagnostics.start_progress(200)
    49.times { diagnostics.progress(killed) }
    expect(err.string).not_to include("\r", "49/200")
    diagnostics.progress(killed)
    expect(err.string).to include(".", "50/200 (25%)")
    50.times { diagnostics.progress(killed) }
    expect(err.string).to include("100/200 (50%)")
    expect(err.string.scan("/200").size).to eq(2)
  end

  it "does not need an output that answers tty?" do
    plain = Class.new do
      attr_reader :text

      def initialize = @text = +""
      def puts(*lines) = @text << lines.join("\n") << "\n"
      def print(*parts) = @text << parts.join
      def flush; end
    end.new
    quiet = described_class.new(plain)
    quiet.start_progress(2)
    quiet.progress(killed)
    expect(plain.text).to include(".")
  end

  it "ends a terminal line with a newline even when the count is a multiple of the line width" do
    allow(err).to receive(:tty?).and_return(true)
    diagnostics.start_progress(100)
    50.times { diagnostics.progress(killed) }
    before = err.string.dup
    diagnostics.finish_progress
    expect(err.string).to eq("#{before}\n")
  end

  it "prints nothing at finish when no progress was started, even on a terminal" do
    allow(err).to receive(:tty?).and_return(true)
    diagnostics.finish_progress
    expect(err.string).to eq("")
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
