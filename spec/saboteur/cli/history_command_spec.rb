# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe "saboteur badge and saboteur trend (#474)" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      @history = File.join(dir, "history.jsonl")
      example.run
    end
  end

  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    code = Saboteur::CLI.new(argv, out: out, err: err).call
    [code, out.string, err.string]
  end

  def append(*results, scope: { "seed" => 1 }, policy: nil)
    Saboteur::Reporter::ScoreHistory.new(@history)
                                    .append(report_of(*results, policy: policy), head: "a" * 40, scope: scope)
  end

  def badge_json(out)
    JSON.parse(File.exist?(File.join(@dir, "badge.json")) ? File.read(File.join(@dir, "badge.json")) : out)
  end

  it "badge writes Shields endpoint JSON for the latest record, colored by the thresholds" do
    append(result_for(:killed, kill_cause: "assertion"), result_for(:survived))
    code, out, err = cli("badge", "--history", @history)
    expect([code, err]).to eq([0, ""])
    expect(JSON.parse(out)).to eq("schemaVersion" => 1, "label" => "mutation score",
                                  "message" => "50.0%", "color" => "red")
    append(result_for(:killed, kill_cause: "assertion"))
    code, = cli("badge", "--history", @history, "--output", File.join(@dir, "badge.json"))
    expect(code).to eq(0)
    expect(badge_json(out)).to include("message" => "100.0%", "color" => "brightgreen")
  end

  it "badge refuses an incomplete run unless --mark-partial labels it" do
    append(result_for(:killed, kill_cause: "assertion"), result_for(:skipped, replacement: "<", reason: "no coverage"))
    code, _out, err = cli("badge", "--history", @history)
    expect(code).to eq(3)
    expect(err).to include("incomplete").and include("--mark-partial")
    code, out, = cli("badge", "--history", @history, "--mark-partial")
    expect(code).to eq(0)
    expect(JSON.parse(out).fetch("label")).to eq("mutation score (partial)")
  end

  it "badge fails clearly on missing history, and with exit 2 when no history path exists at all" do
    code, _out, err = cli("badge", "--history", File.join(@dir, "absent.jsonl"))
    expect(code).to eq(3)
    expect(err).to include("cannot be read")
    Dir.chdir(@dir) do
      code, _out, err = cli("badge")
      expect(code).to eq(2)
      expect(err).to include("--history")
    end
  end

  it "trend prints the delta against the last comparable record and never mixes configurations" do
    append(result_for(:survived))
    append(result_for(:killed, kill_cause: "assertion"), scope: { "seed" => 2 })
    code, out, = cli("trend", "--history", @history)
    expect(code).to eq(0)
    expect(out).to include("100.0%")
    expect(out).to include("no comparable earlier record")
    expect(out).not_to include("percentage points")
    append(result_for(:killed, kill_cause: "assertion"), scope: { "seed" => 2 })
    code, out, = cli("trend", "--history", @history)
    expect(code).to eq(0)
    expect(out).to include("+0.00 percentage points")
  end
end
