# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/reporter/score_history"
require "saboteur/reporter/history_paths"
require "timeout"

RSpec.describe "history safety" do
  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, "history.jsonl")
      example.run
    end
  end

  def writer
    Saboteur::Reporter::ScoreHistory.new(@path)
  end

  def append
    writer.append(report_of(result_for(:killed)), head: "a" * 40, scope: {})
  end

  it "refuses FIFOs and devices promptly without reading or changing them" do
    File.mkfifo(@path)
    Timeout.timeout(1) do
      expect { append }.to raise_error(Saboteur::Error, /regular file/)
      expect { writer.validate_existing }.to raise_error(Saboteur::Error, /regular file/)
      device = Saboteur::Reporter::ScoreHistory.new(File::NULL)
      expect { device.validate_existing }.to raise_error(Saboteur::Error, /regular file/)
    end
    expect(File).to be_pipe(@path)
  end

  it "bounds individual records before JSON parsing, preserving bytes" do
    text = "x" * (Saboteur::Reporter::ScoreHistory::MAX_RECORD_BYTES + 1)
    File.write(@path, text)
    expect { append }.to raise_error(Saboteur::Error, /byte limit/)
    expect(File.read(@path)).to eq(text)
    expect { writer.validate_existing }.to raise_error(Saboteur::Error, /byte limit/)
  end

  it "rejects duplicate keys at top level and nested counts" do
    append
    original = File.read(@path)
    [original.sub('"version":1', '"version":1,"version":1'),
     original.sub('"killed":1', '"killed":1,"killed":1')].each do |text|
      File.write(@path, text)
      expect { append }.to raise_error(Saboteur::Error, /duplicate/)
      expect(File.read(@path)).to eq(text)
    end
  end

  it "requires every record field and validates all value types" do
    append
    valid = JSON.parse(File.read(@path))
    invalid = valid.keys.map { |key| valid.except(key) }
    invalid += [{ "date" => "no date" }, { "commit" => "short" }, { "score" => 2 },
                { "counts" => {} }, { "breakdown" => {} }, { "incomplete" => [1] },
                { "incomplete" => [""] }, { "incomplete" => %w[errors errors] }].map { |row| valid.merge(row) }
    invalid << valid.merge("counts" => valid["counts"].merge("killed" => -1))
    invalid << valid.merge("counts" => valid["counts"].merge("killed" => 1.5))
    invalid << valid.merge("breakdown" => valid["breakdown"].merge("tested" => 2))
    invalid.each do |row|
      text = "#{JSON.generate(row)}\n"
      File.write(@path, text)
      expect { append }.to raise_error(Saboteur::Error)
      expect(File.read(@path)).to eq(text)
    end
  end

  it "rejects symlinks, parent-directory symlinks and hardlink collisions" do
    append
    sibling = "#{@path}.report"
    File.link(@path, sibling)
    expect { Saboteur::Reporter::HistoryPaths.validate([@path, sibling]) }
      .to raise_error(Saboteur::Error, /alias/)
    File.unlink(sibling)
    File.symlink(@path, sibling)
    expect { Saboteur::Reporter::HistoryPaths.validate([@path, sibling]) }
      .to raise_error(Saboteur::Error, /symlinks/)
    link = File.join(File.dirname(@path), "linked")
    File.symlink(File.dirname(@path), link)
    expect { Saboteur::Reporter::HistoryPaths.validate([File.join(link, "new.json")]) }
      .to raise_error(Saboteur::Error, /symlinks/)
    expect { Saboteur::Reporter::HistoryPaths.validate([@path, "#{@path}.new"]) }.not_to raise_error
  end
  it "checks descriptor regularity even when the path looked normal" do
    append
    file = File.open(@path, File::RDWR) # rubocop:disable Style/FileOpen
    begin
      allow(File).to receive(:open).with(@path, Saboteur::Reporter::ScoreHistory::OPEN_FLAGS, 0o600).and_yield(file)
      allow(file).to receive(:stat).and_return(instance_double(File::Stat, file?: false))
      expect { append }.to raise_error(Saboteur::Error, /regular file/)
    ensure
      file.close
    end
  end

  it "does not wait forever for a history read lock" do
    append
    File.open(@path, File::RDONLY) do |file|
      allow(File).to receive(:open).and_yield(file)
      allow(file).to receive(:flock).and_return(false)
      allow(Process).to receive(:clock_gettime).and_return(0, 3)
      expect { writer.validate_existing }.to raise_error(Saboteur::Error, /lock was not acquired/)
    end
  end

  it "uses the exact bounded retry deadline and yields before retrying" do
    target = writer
    file = instance_double(File)
    mode = File::LOCK_EX
    expect(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10).ordered
    expect(file).to receive(:flock).with(mode | File::LOCK_NB).and_return(false).ordered
    expect(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(11).ordered
    expect(target).to receive(:sleep).with(0.01).ordered
    expect(file).to receive(:flock).with(mode | File::LOCK_NB).and_return(false).ordered
    expect(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(12).ordered
    expect { target.send(:lock, file, mode) }.to raise_error(Saboteur::Error, /lock was not acquired/)
  end

  it "allows immediate retry success before the deadline" do
    target = writer
    file = instance_double(File)
    expect(file).to receive(:flock).with(File::LOCK_EX | File::LOCK_NB).and_return(false, true)
    expect(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10, 11)
    expect(target).to receive(:sleep).with(0.01)
    expect { target.send(:lock, file, File::LOCK_EX) }.not_to raise_error
  end

  it "uses a bounded byte reader and accepts a line exactly at the limit" do
    file = instance_double(File)
    limit = Saboteur::Reporter::ScoreHistory::MAX_RECORD_BYTES
    line = "#{' ' * (limit - 1)}\n"
    expect(file).to receive(:gets).with(limit + 1).and_return(line, nil)
    expect(Saboteur::Reporter::HistoryRecord).to receive(:parse).with(line).and_return({})
    expect(writer.send(:previous_record, file)).to eq({})
  end

  it "returns nil for an empty bounded reader" do
    file = instance_double(File)
    expect(file).to receive(:gets).with(Saboteur::Reporter::ScoreHistory::MAX_RECORD_BYTES + 1).and_return(nil)
    expect(writer.send(:previous_record, file)).to be_nil
  end

  it "does not open absent history but rejects dangling history links" do
    expect(File).not_to receive(:open)
    expect { writer.validate_existing }.not_to raise_error
    RSpec::Mocks.space.proxy_for(File).reset
    File.symlink("#{@path}.missing", @path)
    expect { writer.validate_existing }.to raise_error(Saboteur::Error)
  end

  it "validates its new observation before opening any destination" do
    report = report_of(result_for(:killed))
    expect(Saboteur::Reporter::HistoryRecord).to receive(:validate).and_raise(Saboteur::Error, "invalid observation")
    expect(File).not_to receive(:open)
    expect { writer.append(report, head: "a" * 40, scope: {}) }.to raise_error(Saboteur::Error, /invalid observation/)
  end
  it "expands relative destinations and removes nil output paths" do
    paths = [nil, "relative-history"]
    expect(File).to receive(:expand_path).with("relative-history").and_return(@path)
    expect { Saboteur::Reporter::HistoryPaths.validate(paths) }.not_to raise_error
  end

  it "refuses nonregular report destinations as well as history" do
    File.mkfifo(@path)
    expect { Saboteur::Reporter::HistoryPaths.validate([@path]) }
      .to raise_error(Saboteur::Error, /destination must be a regular file/)
  end

  it "checks every parent and terminates when reaching the filesystem root" do
    probe = Saboteur::Reporter::HistoryPaths
    %w[/one/two /one /].each { |path| expect(File).to receive(:symlink?).with(path).and_return(false).ordered }
    expect(probe.reject_links("/one/two")).to be_nil
  end
  it "prints the exact unavailable messages for incompatible records and absent scores" do
    base = { "selection" => "a", "inventory" => "b", "incomplete" => [], "coveredScore" => nil }
    expect(writer.send(:change, base, base.merge("selection" => "other")))
      .to eq("score history: change unavailable (different selection/inventory or incomplete run)")
    expect(writer.send(:change, base, base))
      .to eq("score history: change unavailable (no tested mutants)")
  end
  it "refuses oversized new observations before opening any output" do
    report = report_of(result_for(:killed))
    allow(Saboteur::Reporter::Agent::Incomplete).to receive(:reasons)
      .and_return([{ reason: "x" * Saboteur::Reporter::ScoreHistory::MAX_RECORD_BYTES }])
    expect(File).not_to receive(:open)
    expect { writer.append(report, head: "a" * 40, scope: {}) }.to raise_error(Saboteur::Error, /byte limit/)
  end
  it "accepts new observations exactly at the record-size boundary" do
    report = report_of(result_for(:killed))
    record = writer.send(:build, report, "a" * 40, {})
    length = "#{JSON.generate(record)}\n".bytesize
    stub_const("Saboteur::Reporter::ScoreHistory::MAX_RECORD_BYTES", length)
    expect { append }.not_to raise_error
    expect(File.size(@path)).to eq(length)
  end
end
