# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "timeout"
require "tmpdir"

RSpec.describe Saboteur::Reporter::HistoryReader do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      @history = File.join(dir, "history.jsonl")
      example.run
    end
  end

  def append(*results, scope: { "seed" => 1 }, policy: nil)
    Saboteur::Reporter::ScoreHistory.new(@history)
                                    .append(report_of(*results, policy: policy), head: "a" * 40, scope: scope)
  end

  def record_with(**changes)
    append(result_for(:killed, kill_cause: "assertion"))
    JSON.parse(File.read(@history)).merge(changes.transform_keys(&:to_s))
  end

  describe ".read" do
    it "returns every record in file order" do
      append(result_for(:killed, kill_cause: "assertion"))
      append(result_for(:survived))
      expect(described_class.read(@history).map { |record| record["coveredScore"] }).to eq([1.0, 0.0])
    end

    it "returns no records for an empty file" do
      File.write(@history, "")
      expect(described_class.read(@history)).to eq([])
    end

    it "waits for a writer that holds the exclusive lock before reading" do
      append(result_for(:killed, kill_cause: "assertion"))
      File.open(@history, File::RDWR) do |writer|
        writer.flock(File::LOCK_EX)
        reader = Thread.new { described_class.read(@history) }
        sleep 0.2
        expect(reader).to be_alive
        writer.flock(File::LOCK_UN)
        expect(Timeout.timeout(2) { reader.value }.size).to eq(1)
      end
    end

    it "refuses a path that is not a regular file" do
      fifo = File.join(@dir, "pipe.jsonl")
      File.mkfifo(fifo)
      expect { Timeout.timeout(2) { described_class.read(fifo) } }
        .to raise_error(Saboteur::Error, "score history must be a regular file")
    end

    it "refuses a symlink without following it" do
      append(result_for(:killed, kill_cause: "assertion"))
      link = File.join(@dir, "link.jsonl")
      File.symlink(@history, link)
      expect { described_class.read(link) }
        .to raise_error(Saboteur::Error, /\Ascore history cannot be read: /)
    end

    it "names an unreadable path" do
      expect { described_class.read(File.join(@dir, "absent.jsonl")) }
        .to raise_error(Saboteur::Error, /\Ascore history cannot be read: No such file or directory/)
    end

    # This fixture's line is exactly limit + 1 bytes on disk, so it pins the
    # gets(limit + 1) read length: gets(limit) reads one byte short, misses
    # the newline, and raises "truncated record" instead.
    it "refuses a record longer than the byte limit" do
      limit = Saboteur::Reporter::ScoreHistory::MAX_RECORD_BYTES
      File.write(@history, "#{'x' * limit}\n#{'y' * 10}\n")
      expect { described_class.read(@history) }
        .to raise_error(Saboteur::Error, "score history record exceeds byte limit")
    end

    it "accepts a record of exactly the byte limit, up to the validation step" do
      limit = Saboteur::Reporter::ScoreHistory::MAX_RECORD_BYTES
      File.write(@history, "#{'x' * (limit - 1)}\n")
      expect { described_class.read(@history) }
        .to raise_error(Saboteur::Error, /\Ascore history contains an invalid record/)
    end

    # A mocked IO is the only observable difference for the read length: any
    # oversized line raises the same byte-limit error however many bytes gets
    # pulls, but dropping the length argument unbounds the read.
    it "bounds each record read to the byte limit plus one byte (#526)" do
      limit = Saboteur::Reporter::ScoreHistory::MAX_RECORD_BYTES
      file = instance_double(File)
      allow(File).to receive(:open).and_yield(file)
      allow(file).to receive(:stat).and_return(instance_double(File::Stat, file?: true))
      allow(file).to receive(:flock)
      allow(file).to receive(:gets).with(limit + 1).and_return(nil)
      expect(described_class.read(@history)).to eq([])
    end

    it "refuses a final record with no newline" do
      append(result_for(:killed, kill_cause: "assertion"))
      File.write(@history, File.read(@history).chomp)
      expect { described_class.read(@history) }
        .to raise_error(Saboteur::Error, "score history contains a truncated record")
    end

    it "refuses a record that is not valid evidence" do
      File.write(@history, "{}\n")
      expect { described_class.read(@history) }.to raise_error(Saboteur::Error)
    end
  end

  describe ".comparable?" do
    let(:base) do
      { "version" => 1, "selection" => "s", "inventory" => "i", "incomplete" => [], "operatorPolicy" => "p" }
    end

    it "accepts two complete records with the same version, selection, inventory and policy" do
      expect(described_class.comparable?(base, base.dup)).to be(true)
    end

    it "rejects each difference" do
      { "version" => 2, "selection" => "t", "inventory" => "j", "operatorPolicy" => "q" }.each do |key, value|
        expect(described_class.comparable?(base, base.merge(key => value))).to be(false), key
      end
    end

    it "rejects an incomplete record on either side" do
      expect(described_class.comparable?(base.merge("incomplete" => ["x"]), base)).to be(false)
      expect(described_class.comparable?(base, base.merge("incomplete" => ["x"]))).to be(false)
    end

    it "never compares a null operator policy, even to another null" do
      nulls = base.merge("operatorPolicy" => nil)
      expect(described_class.comparable?(nulls, nulls.dup)).to be(false)
      expect(described_class.comparable?(base, nulls)).to be(false)
    end
  end
end
