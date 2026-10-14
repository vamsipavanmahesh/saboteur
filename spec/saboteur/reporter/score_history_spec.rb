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
    expect(row).to include("version" => 2, "commit" => "a" * 40, "score" => 1.0, "coveredScore" => 1.0)
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
    unavailable = "score history: change unavailable (different selection/inventory or incomplete run)"
    append(report_of(result_for(:killed)))
    expect(append(report_of(result_for(:killed)), scope: { "seed" => 2 })).to include(unavailable)
    expect(append(report_of(result_for(:killed, replacement: "<")))).to include(unavailable)
    expect(append(report_of(result_for(:error)))).to include(unavailable)
  end

  it "stores null for empty scores and does not invent a delta" do
    empty = report_of
    append(empty)
    expect(records.first.fetch("coveredScore")).to be_nil
    expect(append(empty)).to include("score history: change unavailable (no tested mutants)")
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

  it "records the operator policy and reads legacy v1 without comparing across policy versions" do
    report = report_of(result_for(:killed))
    config = Saboteur::Config.new({ "exclude_operators" => ["range"] })
    allow(report).to receive(:operator_policy).and_return(config.operator_policy)
    append(report)
    row = records.first
    expect(row["operatorPolicy"]).to eq(config.operator_policy)
    legacy = row.except("operatorPolicy").merge("version" => 1, "selection" => "0" * 64)
    File.write(@path, "#{JSON.generate(legacy)}\n")
    expect { described_class.new(@path).validate_existing }.not_to raise_error
    expect(append(report)).to include("change unavailable")
  end

  it "rejects v2 records with a null or empty-effective operator policy" do
    append(report_of(result_for(:killed)))
    valid = records.first
    [valid.merge("operatorPolicy" => nil),
     valid.merge("operatorPolicy" => Saboteur::MutationSource::OperatorRegistry.policy(
       [], Saboteur::MutationSource::OperatorRegistry::DESCRIPTIONS.keys
     ))].each do |row|
      text = "#{JSON.generate(row)}\n"
      File.write(@path, text)
      expect { append(report_of(result_for(:killed))) }.to raise_error(Saboteur::Error, /invalid operator policy/)
      expect(File.read(@path)).to eq(text)
    end
  end

  it "withholds deltas across record versions and operator policies, even with matching hashes" do
    report = report_of(result_for(:killed))
    append(report)
    first = records.first
    File.write(@path, "#{JSON.generate(first.except('operatorPolicy').merge('version' => 1))}\n")
    expect(append(report)).to include("change unavailable")
    other = Saboteur::Config.new({ "exclude_operators" => ["range"] }).operator_policy
    File.write(@path, "#{JSON.generate(first.merge('operatorPolicy' => other))}\n")
    expect(append(report)).to include("change unavailable")
    File.write(@path, "#{JSON.generate(first)}\n")
    expect(append(report_of(result_for(:survived)))).to include("-100.00 percentage points")
  end

  it "compares policies only when both records carry one" do
    history = described_class.new(@path)
    policy = Saboteur::Config.new({}).operator_policy
    with_policy = { "version" => 2, "operatorPolicy" => policy }
    without_policy = { "version" => 2, "operatorPolicy" => nil }
    expect(history.send(:comparable_policy?, without_policy, with_policy)).to be(false)
    expect(history.send(:comparable_policy?, without_policy, without_policy)).to be(false)
    expect(history.send(:comparable_policy?, with_policy, without_policy)).to be(false)
    expect(history.send(:comparable_policy?, with_policy, with_policy)).to be(true)
    other = with_policy.merge("version" => 1, "operatorPolicy" => nil)
    expect(history.send(:comparable_policy?, other, other)).to be(false)
  end

  it "isolates every prior-record schema guard" do
    append(report_of(result_for(:killed)))
    valid = records.first
    variants = [{ "version" => 3 }, { "selection" => nil }, { "inventory" => nil },
                { "incomplete" => nil }].map { |change| valid.merge(change) }
    variants << valid.except("coveredScore")
    variants.each do |row|
      text = "#{JSON.generate(row)}\n"
      File.write(@path, text)
      expect { append(report_of(result_for(:killed))) }.to raise_error(Saboteur::Error, /invalid/)
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
      expect(append(report)).to include("score history: change unavailable (no tested mutants)")
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
    expect(File).to receive(:open).with(@path, described_class::OPEN_FLAGS, 0o600).and_call_original
    append(report_of(result_for(:killed)))
    File.open(@path, File::RDWR) do |file|
      allow(File).to receive(:open).with(@path, described_class::OPEN_FLAGS, 0o600).and_yield(file)
      expect(file).to receive(:flock).with(File::LOCK_EX | File::LOCK_NB).and_call_original
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
      allow(Process).to receive(:clock_gettime).and_return(0, 3)
      expect { append(report_of(result_for(:killed))) }.to raise_error(Saboteur::Error, /lock was not acquired/)
    end
    expect(File.read(@path)).to eq(original)
  end

  it "fails instead of overwriting a directory" do
    FileUtils.mkdir_p(@path)
    expect { append(report_of(result_for(:killed))) }.to raise_error(Saboteur::Error, /not recorded/)
  end
end
