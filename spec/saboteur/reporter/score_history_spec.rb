# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/reporter/score_history"

RSpec.describe Saboteur::Reporter::ScoreHistory do
  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, "history.jsonl")
      example.run
    end
  end

  def append(report, scope: { "seed" => 1 })
    described_class.new(@path).append(report, head: "a" * 40, scope: scope)
  end

  def records
    File.readlines(@path).map { |line| JSON.parse(line) }
  end

  it "records one dated commit, score, covered score, counts and kill breakdown per run" do
    expect(append(report_of(result_for(:killed, kill_cause: "assertion")))).to include("first record")
    row = records.first
    expect(row).to include("version" => 1, "commit" => "a" * 40, "score" => 1.0, "coveredScore" => 1.0)
    expect(Time.iso8601(row.fetch("date"))).to be_a(Time)
    expect(row.fetch("counts")["killed"]).to eq(1)
    expect(row.fetch("breakdown")["assertionKills"]).to eq(1)
    expect(row.fetch("incomplete")).to eq([])
  end

  it "records overall separately when observed mutants have no coverage" do
    append(report_of(result_for(:killed), result_for(:skipped, replacement: "<", reason: "no coverage")))
    expect(records.first).to include("score" => 0.5, "coveredScore" => 1.0)
    expect(records.first["incomplete"]).to include("no_coverage")
  end

  it "prints signed percentage-point change only for the same configuration and inventory" do
    append(report_of(result_for(:killed)))
    expect(append(report_of(result_for(:survived)))).to include("-100.00 percentage points")
    expect(append(report_of(result_for(:killed)))).to include("+100.00 percentage points")
    expect(records.size).to eq(3)
  end

  it "withholds deltas for different selections, mutant identities and incomplete runs" do
    append(report_of(result_for(:killed)))
    expect(append(report_of(result_for(:killed)), scope: { "seed" => 2 })).to include("change unavailable")
    expect(append(report_of(result_for(:killed, replacement: "<")))).to include("change unavailable")
    expect(append(report_of(result_for(:error)))).to include("change unavailable")
  end

  it "stores null for empty scores and does not invent a delta" do
    empty = report_of
    append(empty)
    expect(records.first.fetch("coveredScore")).to be_nil
    expect(append(empty)).to include("no tested mutants")
  end

  it "leaves corrupt and truncated history unchanged" do
    ["not-json\n", "{}\n", '{"version":1'].each do |text|
      File.write(@path, text)
      expect { append(report_of(result_for(:killed))) }.to raise_error(Saboteur::Error)
      expect(File.read(@path)).to eq(text)
    end
  end

  it "rejects a complete JSON record lacking its newline instead of joining records" do
    append(report_of(result_for(:killed)))
    text = File.read(@path).chomp
    File.write(@path, text)
    expect { append(report_of(result_for(:killed))) }.to raise_error(Saboteur::Error, /truncated/)
    expect(File.read(@path)).to eq(text)
  end

  it "serializes concurrent appenders without losing or joining records" do
    pids = Array.new(3) do
      fork do
        2.times { append(report_of(result_for(:killed))) }
        exit!(0)
      end
    end
    statuses = pids.map { |pid| Process.waitpid2(pid).last }
    expect(statuses).to all(be_success)
    expect(records.size).to eq(6)
    expect(records).to all(include("coveredScore" => 1.0))
  end

  it "rejects nonnumeric or out-of-range prior scores before writing" do
    append(report_of(result_for(:killed)))
    row = records.first
    ["bad", -1, 2].each do |invalid|
      text = "#{JSON.generate(row.merge('coveredScore' => invalid))}\n"
      File.write(@path, text)
      expect { append(report_of(result_for(:killed))) }.to raise_error(Saboteur::Error, /invalid score/)
      expect(File.read(@path)).to eq(text)
    end
  end

  it "isolates every prior-record schema guard" do
    append(report_of(result_for(:killed)))
    valid = records.first
    variants = [{ "version" => 2 }, { "selection" => nil }, { "inventory" => nil },
                { "incomplete" => nil }].map { |change| valid.merge(change) }
    variants << valid.except("coveredScore")
    variants.each do |row|
      text = "#{JSON.generate(row)}\n"
      File.write(@path, text)
      expect { append(report_of(result_for(:killed))) }.to raise_error(Saboteur::Error, /invalid record/)
      expect(File.read(@path)).to eq(text)
    end
  end

  it "isolates both selection guards and both incomplete guards" do
    base = report_of(result_for(:killed))
    variants = [report_of(result_for(:killed, replacement: "<")),
                report_of(result_for(:error))]
    variants.each do |variant|
      FileUtils.rm_f(@path)
      append(base)
      expect(append(variant)).to include("different selection/inventory or incomplete run")
      FileUtils.rm_f(@path)
      append(variant)
      expect(append(base)).to include("different selection/inventory or incomplete run")
    end
  end

  it "isolates either side of a missing score with the same mutant inventory" do
    [%i[skipped survived], %i[survived skipped]].each do |before, after|
      FileUtils.rm_f(@path)
      append(report_of(result_for(before, reason: "no coverage")))
      row = records.first.merge("incomplete" => [])
      File.write(@path, "#{JSON.generate(row)}\n")
      report = report_of(result_for(after))
      allow(Saboteur::Reporter::Agent::Incomplete).to receive(:reasons).and_return([])
      expect(append(report)).to include("no tested mutants")
    end
  end

  it "does not count unrelated skips or a reason attached to a non-skipped verdict as NoCoverage" do
    append(report_of(result_for(:killed, reason: "no coverage"),
                     result_for(:skipped, replacement: "<", reason: "unavailable")))
    expect(records.first).to include("score" => 1.0, "coveredScore" => 1.0)
  end

  it "records producer incompleteness and explicit omissions without inventing either" do
    [true, false].each do |complete|
      report = report_of(result_for(:killed))
      allow(report).to receive(:run_evidence).and_return("complete" => complete)
      allow(report).to receive(:omissions).and_return([Object.new])
      append(report)
      reasons = records.last.fetch("incomplete")
      expect(reasons).to include("omissions")
      expect(reasons.include?("baseline_incomplete")).to eq(!complete)
    end
    append(report_of(result_for(:killed)))
    expect(records.last.fetch("incomplete")).to eq([])
  end

  it "creates missing directories, seeks to end, flushes and requests a private locked file" do
    @path = File.join(File.dirname(@path), "nested", "history.jsonl")
    allow(File).to receive(:open).and_call_original
    expect(File).to receive(:open).with(@path, File::RDWR | File::CREAT, 0o600).and_call_original
    append(report_of(result_for(:killed)))
    File.open(@path, File::RDWR) do |file|
      allow(File).to receive(:open).with(@path, File::RDWR | File::CREAT, 0o600).and_yield(file)
      expect(file).to receive(:flock).with(File::LOCK_EX).and_call_original
      expect(file).to receive(:seek).with(0, IO::SEEK_END).and_call_original
      expect(file).to receive(:flush).and_call_original
      expect(append(report_of(result_for(:killed)))).to include("+0.00 percentage points")
    end
    expect(records.size).to eq(2)
  end

  it "refuses a failed lock without writing" do
    append(report_of(result_for(:killed)))
    original = File.read(@path)
    File.open(@path, File::RDWR) do |file|
      allow(File).to receive(:open).and_yield(file)
      allow(file).to receive(:flock).and_return(false)
      expect { append(report_of(result_for(:killed))) }.to raise_error(Saboteur::Error, /lock was not acquired/)
    end
    expect(File.read(@path)).to eq(original)
  end

  it "fails instead of overwriting a directory" do
    FileUtils.mkdir_p(@path)
    expect { append(report_of(result_for(:killed))) }.to raise_error(Saboteur::Error, /not recorded/)
  end
end
