# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

# Pins for the output capture helpers of ExternalRunner. The pipe and thread
# are stubbed, so no process or real pipe is involved.
RSpec.describe Saboteur::Execution::ExternalRunner, "capture pins" do
  let(:root) { File.realpath(Dir.mktmpdir("ext-cap")) }
  let(:runner) { described_class.new(command: "true", root: root) }
  let(:limit) { described_class::OUTPUT_LIMIT }

  after do
    runner.close
    FileUtils.remove_entry(root)
  end

  def ivar(name) = runner.instance_variable_get(name)

  describe "#start_capture" do
    def feed(chunks, gate: nil)
      reader = double("reader")
      allow(reader).to receive(:readpartial).with(16_384) do
        gate&.pop if chunks.empty?
        chunks.empty? ? raise(EOFError) : chunks.shift
      end
      allow(IO).to receive(:pipe).and_return([reader, double("writer")])
    end

    def drain(*chunks)
      feed(chunks.dup)
      runner.send(:start_capture)
      ivar(:@capture_thread).join
      ivar(:@capture_buffer)
    end

    it "reads the pipe in 16 KiB chunks" do
      expect(drain("abc", "def")).to eq("abcdef")
    end

    it "keeps output that is exactly at the limit without re-slicing it" do
      gate = Queue.new
      feed(["x" * limit], gate: gate)
      runner.send(:start_capture)
      buffer = ivar(:@capture_buffer)
      gate.push(:go)
      ivar(:@capture_thread).join
      expect(ivar(:@capture_buffer)).to equal(buffer)
      expect(buffer.bytesize).to eq(limit)
    end

    it "keeps only the last OUTPUT_LIMIT bytes once the output grows past it" do
      head = "a" * 10
      tail = "#{'b' * (limit - 5)}TAIL!"
      buffer = drain(head, tail)
      expect(buffer.bytesize).to eq(limit)
      expect(buffer).to end_with("TAIL!")
      expect(buffer).not_to include("a")
    end
  end

  describe "#finish_capture" do
    let(:writer) { double("writer", close: nil) }
    let(:reader) { double("reader", close: nil) }
    let(:thread) { double("thread", join: true, kill: nil) }

    def arm(reader: self.reader, thread: self.thread)
      runner.instance_variable_set(:@capture_writer, writer)
      runner.instance_variable_set(:@capture_reader, reader)
      runner.instance_variable_set(:@capture_thread, thread)
      runner.instance_variable_set(:@capture_buffer, "captured")
    end

    it "closes both ends, keeps the bytes and clears the capture state" do
      arm
      runner.send(:finish_capture)
      expect(writer).to have_received(:close)
      expect(reader).to have_received(:close)
      expect(ivar(:@captured)).to eq("captured")
      %i[@capture_reader @capture_writer @capture_thread @capture_buffer].each { |name| expect(ivar(name)).to be_nil }
    end

    it "gives the reader the drain grace and does not kill a thread that finished" do
      arm
      runner.send(:finish_capture)
      expect(thread).to have_received(:join).with(described_class::DRAIN_GRACE)
      expect(thread).not_to have_received(:kill)
    end

    it "kills a reader that does not reach EOF in time, then joins it" do
      allow(thread).to receive(:join).with(described_class::DRAIN_GRACE).and_return(nil)
      arm
      runner.send(:finish_capture)
      expect(thread).to have_received(:kill).ordered
      expect(thread).to have_received(:join).with(no_args).ordered
    end

    it "joins the thread once more after a clean drain" do
      arm
      runner.send(:finish_capture)
      expect(thread).to have_received(:join).with(no_args)
    end

    it "copes with a capture that never started" do
      runner.instance_variable_set(:@capture_buffer, "x")
      expect { runner.send(:finish_capture) }.not_to raise_error
      expect(ivar(:@captured)).to eq("x")
    end

    it "copes with a missing reader" do
      arm(reader: nil)
      expect { runner.send(:finish_capture) }.not_to raise_error
    end
  end

  describe "#last_output" do
    def output_for(bytes)
      runner.instance_variable_set(:@captured, bytes)
      runner.send(:last_output)
    end

    it "strips surrounding whitespace" do
      expect(output_for("  hello \n")).to eq("hello")
    end

    it "keeps non-empty output as it is" do
      expect(output_for("x")).to eq("x")
    end

    it "says there was no output for nothing or only whitespace" do
      expect(output_for(nil)).to eq("(no output)")
      expect(output_for(" \n ")).to eq("(no output)")
    end
  end

  describe "#bounded" do
    it "accepts a frozen string and leaves the argument untouched" do
      text = "caf\xC3\xA9".b.freeze
      expect(runner.send(:bounded, text)).to eq("café")
      expect(text.encoding).to eq(Encoding::BINARY)
    end

    it "drops invalid bytes and caps the length" do
      expect(runner.send(:bounded, "a\xFFb")).to eq("ab")
      expect(runner.send(:bounded, "z" * (limit + 5)).length).to eq(limit)
    end
  end

  describe "#describe_exit" do
    it "names each way a command can end" do
      expect(runner.send(:describe_exit, 126)).to eq("exit 126 - the shell could not run the command")
      expect(runner.send(:describe_exit, :signal)).to eq("killed by a signal")
      expect(runner.send(:describe_exit, :timeout)).to eq("timed out")
      expect(runner.send(:describe_exit, RuntimeError.new("boom"))).to eq("could not start: boom")
      expect(runner.send(:describe_exit, 3)).to eq("exit 3")
    end
  end
end
