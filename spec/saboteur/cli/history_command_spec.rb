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

  def history_records
    File.readlines(@history).map { |line| JSON.parse(line) }
  end

  def cli_instance(*argv)
    Saboteur::CLI.new(argv, out: StringIO.new, err: StringIO.new)
  end

  it "badge --help golden: banner, every option and its default" do
    expected = "Usage: saboteur badge [--history PATH] [--output PATH] [--mark-partial] " \
               "[--high PERCENT] [--low PERCENT]\n        " \
               "--history PATH               Score history JSONL (default: c.score_history)\n        " \
               "--output PATH                Badge JSON destination (default: stdout)\n        " \
               "--mark-partial               Badge an incomplete run, labeled as partial\n        " \
               "--high PERCENT               brightgreen at or above (default 80)\n        " \
               "--low PERCENT                yellow at or above (default 60)\n        " \
               "--color [MODE]               Colour the text report: always, never or auto (default: auto)\n        " \
               "--no-color                   Deprecated alias for --color=never\n"
    expect(cli_instance("badge").badge_parser.help).to eq(expected)
  end

  it "trend --help golden: banner and the history option" do
    expected = "Usage: saboteur trend [--history PATH]\n        " \
               "--history PATH               Score history JSONL (default: c.score_history)\n        " \
               "--color [MODE]               Colour the text report: always, never or auto (default: auto)\n        " \
               "--no-color                   Deprecated alias for --color=never\n"
    expect(cli_instance("trend").trend_parser.help).to eq(expected)
  end

  it "badge --help and trend -h print their help instead of reading history" do
    # Without the dispatch, badge --help reaches badge_parser, whose officious
    # --help handler prints the parser help and EXITS the process; the
    # raise_error guard turns that into a clean failure instead of
    # truncating the whole suite at a random point.
    expect { cli("badge", "--help") }.not_to raise_error
    code, out, err = cli("badge", "--help")
    expect([code, err]).to eq([0, ""])
    expect(out).to include("saboteur badge")
    expect { cli("trend", "-h") }.not_to raise_error
    code, out, err = cli("trend", "-h")
    expect([code, err]).to eq([0, ""])
    expect(out).to include("saboteur trend")
  end

  it "badge --help reaches the help dispatch through CLI#call and never runs badge" do
    out = StringIO.new
    instance = Saboteur::CLI.new(%w[badge --help], out: out, err: StringIO.new)
    allow(instance).to receive(:badge)
    expect(instance.call).to eq(0)
    expect(out.string).to start_with("saboteur badge - ")
    expect(instance).not_to have_received(:badge)
  end

  it "trend --help reaches the help dispatch through CLI#call and never runs trend" do
    out = StringIO.new
    instance = Saboteur::CLI.new(%w[trend --help], out: out, err: StringIO.new)
    allow(instance).to receive(:trend)
    expect(instance.call).to eq(0)
    expect(out.string).to start_with("saboteur trend - ")
    expect(instance).not_to have_received(:trend)
  end

  it "badge --high/--low parse as floats and steer the color at exact boundaries" do
    append(result_for(:killed, kill_cause: "assertion"), *Array.new(19) { result_for(:survived) })
    # 1/20 killed = exactly 5.0%.
    code, out, = cli("badge", "--history", @history, "--low", "6", "--high", "7")
    expect(code).to eq(0)
    expect(JSON.parse(out).fetch("color")).to eq("red")
    _code, out, = cli("badge", "--history", @history, "--low", "5", "--high", "6")
    expect(JSON.parse(out).fetch("color")).to eq("yellow")
    _code, out, = cli("badge", "--history", @history, "--low", "1", "--high", "5")
    expect(JSON.parse(out).fetch("color")).to eq("brightgreen")
    # Fractional thresholds must parse as floats, not integers.
    _code, out, = cli("badge", "--history", @history, "--low", "1", "--high", "5.5")
    expect(JSON.parse(out).fetch("color")).to eq("yellow")
  end

  it "badge colors sit exactly on the default thresholds" do
    # 80% exactly: brightgreen (>=, not >); 79% would be yellow.
    results = Array.new(4) { result_for(:killed, kill_cause: "assertion") } + [result_for(:survived)]
    append(*results)
    _code, out, = cli("badge", "--history", @history)
    expect(JSON.parse(out).fetch("color")).to eq("brightgreen")
    # 60% exactly: yellow (>=, not >, and not ==); 59% would be red.
    results = Array.new(3) { result_for(:killed, kill_cause: "assertion") } + Array.new(2) { result_for(:survived) }
    append(*results)
    _code, out, = cli("badge", "--history", @history)
    expect(JSON.parse(out).fetch("color")).to eq("yellow")
  end

  it "badge prints the payload with a trailing newline, and the output path when written to a file" do
    append(result_for(:killed, kill_cause: "assertion"))
    code, out, = cli("badge", "--history", @history)
    expect(code).to eq(0)
    expect(out).to eq(%({"schemaVersion":1,"label":"mutation score","message":"100.0%","color":"brightgreen"}\n))
    badge = File.join(@dir, "badge.json")
    _code, out, = cli("badge", "--history", @history, "--output", badge)
    expect(out).to eq("#{badge}\n")
    expect(File.read(badge)).to end_with("\n")
  end

  it "badge names every incomplete reason in the refusal" do
    append(result_for(:killed, kill_cause: "assertion"),
           result_for(:skipped, replacement: "<", reason: "no coverage"))
    record = history_records.last.merge("incomplete" => ["no coverage", "timeout"])
    File.write(@history, "#{JSON.generate(record)}\n")
    _code, _out, err = cli("badge", "--history", @history)
    expect(err).to include("saboteur: the latest score history record is an incomplete run " +
                           %(("no coverage", "timeout") - ))
    expect(err).to include("--mark-partial")
  end

  it "badge and trend refuse an empty history with the exact empty-history message" do
    File.write(@history, "")
    code, _out, err = cli("badge", "--history", @history)
    expect(code).to eq(3)
    expect(err).to eq("saboteur: score history is empty - record it first by running saboteur " \
                      "with c.score_history set\n")
    code, _out, err = cli("trend", "--history", @history)
    expect(code).to eq(3)
    expect(err).to eq("saboteur: score history is empty - record it first by running saboteur " \
                      "with c.score_history set\n")
  end

  it "badge and trend refuse without --history or c.score_history, with the exact usage message" do
    Dir.chdir(@dir) do
      code, _out, err = cli("badge")
      expect(code).to eq(2)
      expect(err).to eq("saboteur: no score history: pass --history PATH or set c.score_history\n")
      code, _out, err = cli("trend")
      expect(code).to eq(2)
      expect(err).to eq("saboteur: no score history: pass --history PATH or set c.score_history\n")
    end
  end

  it "badge and trend take the history path from c.score_history when --history is not passed" do
    FileUtils.mkdir_p(File.join(@dir, "config"))
    File.write(File.join(@dir, "config", "saboteur.rb"),
               "Saboteur.configure { |c| c.score_history = 'history.jsonl' }\n")
    append(result_for(:survived))
    append(result_for(:killed, kill_cause: "assertion"))
    Dir.chdir(@dir) do
      code, out, = cli("badge")
      expect(code).to eq(0)
      expect(JSON.parse(out).fetch("message")).to eq("100.0%")
      code, out, = cli("trend")
      expect(code).to eq(0)
      expect(out).to include("+100.00 percentage points")
    end
  end

  it "trend never diffs a zero-tested record that reuses the previous record's digests (#526)" do
    # Regression pin: a hand-crafted but valid record with tested zero (nil
    # coveredScore) and the previous record's selection/inventory/policy
    # digests IS comparable - dropping the current coveredScore guard turns
    # the delta subtraction into a NoMethodError crash.
    append(result_for(:survived))
    previous = history_records.last
    zero_tested = previous.merge(
      "counts" => previous["counts"].transform_values { 0 },
      "breakdown" => previous["breakdown"].merge("score" => nil, "tested" => 0, "assertionKills" => 0,
                                                 "crashKills" => 0, "unclassifiedKills" => 0, "timeouts" => 0,
                                                 "survivors" => 0, "assertionShare" => nil, "crashShare" => nil),
      "score" => 0.0, "coveredScore" => nil, "incomplete" => []
    )
    Saboteur::Reporter::HistoryRecord.validate(zero_tested)
    File.write(@history, "#{JSON.generate(previous)}\n#{JSON.generate(zero_tested)}\n")
    code, out, = cli("trend", "--history", @history)
    expect(code).to eq(0)
    expect(out).to include("#{zero_tested['date']} aaaaaaaa no tested mutants\n")
    expect(out).to include("score history: no comparable earlier record (different selection/inventory, " \
                           "operator policy or an incomplete run)\n")
  end

  it "trend never diffs against a zero-tested previous record that shares the current digests (#526)" do
    # Mirror of the zero-tested-current pin: here the OLDER record has a nil
    # coveredScore with the newer record's digests, so comparable? pairs
    # them - dropping the previous coveredScore guard turns the delta
    # subtraction into a NoMethodError crash.
    append(result_for(:survived))
    current = history_records.last
    zero_tested = current.merge(
      "counts" => current["counts"].transform_values { 0 },
      "breakdown" => current["breakdown"].merge("score" => nil, "tested" => 0, "assertionKills" => 0,
                                                "crashKills" => 0, "unclassifiedKills" => 0, "timeouts" => 0,
                                                "survivors" => 0, "assertionShare" => nil, "crashShare" => nil),
      "score" => 0.0, "coveredScore" => nil, "incomplete" => []
    )
    Saboteur::Reporter::HistoryRecord.validate(zero_tested)
    File.write(@history, "#{JSON.generate(zero_tested)}\n#{JSON.generate(current)}\n")
    code, out, = cli("trend", "--history", @history)
    expect(code).to eq(0)
    expect(out).to include("score history: no comparable earlier record (different selection/inventory, " \
                           "operator policy or an incomplete run)\n")
  end

  it "trend does not diff a complete record that has no tested mutants" do
    append(result_for(:survived))
    append
    latest = history_records.last
    code, out, = cli("trend", "--history", @history)
    expect(code).to eq(0)
    expect(out).to include("#{latest['date']} aaaaaaaa no tested mutants\n")
    expect(out).to include("score history: no comparable earlier record (different selection/inventory, " \
                           "operator policy or an incomplete run)\n")
  end

  it "badge escapes control characters in incomplete reasons (#526)" do
    append(result_for(:killed, kill_cause: "assertion"),
           result_for(:skipped, replacement: "<", reason: "no coverage"))
    record = history_records.last.merge("incomplete" => ["no coverage\nspoofed: saboteur run clean"])
    File.write(@history, "#{JSON.generate(record)}\n")
    _code, _out, err = cli("badge", "--history", @history)
    expect(err).to include(%("no coverage\\nspoofed: saboteur run clean"))
    expect(err).not_to include("spoofed: saboteur run clean\n")
    expect(err.lines.size).to eq(1)
  end

  it "trend prints the pair and the exact delta line for a comparable pair" do
    append(result_for(:survived))
    append(result_for(:killed, kill_cause: "assertion"))
    first, last = history_records
    code, out, err = cli("trend", "--history", @history)
    expect([code, err]).to eq([0, ""])
    expect(out).to eq("#{first['date']} #{first['commit'][0, 8]} 0.0%\n" \
                      "#{last['date']} #{last['commit'][0, 8]} 100.0%\n" \
                      "covered score change +100.00 percentage points since #{first['date']} " \
                      "(same configured selection)\n")
  end

  it "trend prints a dash when a record has no commit" do
    append(result_for(:survived))
    record = history_records.last.merge("commit" => nil)
    File.write(@history, "#{JSON.generate(record)}\n")
    _code, out, = cli("trend", "--history", @history)
    expect(out).to include("#{record['date']} - 0.0%\n")
  end

  it "trend marks an incomplete latest record with its suffix" do
    append(result_for(:killed, kill_cause: "assertion"), result_for(:skipped, replacement: "<", reason: "no coverage"))
    record = history_records.last
    _code, out, = cli("trend", "--history", @history)
    expect(out).to include("#{record['date']} #{record['commit'][0, 8]} 100.0% (incomplete)\n")
  end

  it "trend compares against the NEAREST comparable record, not the oldest" do
    append(result_for(:survived))
    append(result_for(:killed, kill_cause: "assertion"))
    append(result_for(:killed, kill_cause: "assertion"))
    _code, out, = cli("trend", "--history", @history)
    expect(out).to include("+0.00 percentage points since #{history_records[1]['date']}")
  end

  it "trend reports no comparable record when the only earlier record is another configuration" do
    append(result_for(:survived), scope: { "seed" => 3 })
    append(result_for(:killed, kill_cause: "assertion"))
    _code, out, = cli("trend", "--history", @history)
    expect(out).to include("aaaaaaaa 100.0%\n")
    expect(out).to include("score history: no comparable earlier record (different selection/inventory, " \
                           "operator policy or an incomplete run)\n")
  end

  it "trend says when no earlier record is comparable, with the full reason" do
    append(result_for(:survived), scope: { "seed" => 9 })
    append(result_for(:killed, kill_cause: "assertion"))
    _code, out, = cli("trend", "--history", @history)
    expect(out).to include("score history: no comparable earlier record (different selection/inventory, " \
                           "operator policy or an incomplete run)\n")
  end

  it "trend shows no tested mutants for a record without a covered score" do
    append(result_for(:skipped, replacement: "<", reason: "no coverage"))
    record = history_records.last
    _code, out, = cli("trend", "--history", @history)
    expect(out).to include("#{record['date']} aaaaaaaa no tested mutants (incomplete)\n")
  end

  it "trend rejects trailing arguments" do
    code, _out, err = cli("trend", "--history", @history, "stray")
    expect(code).to eq(2)
    expect(err).to eq("saboteur: unexpected arguments: stray\n")
  end

  it "badge rejects trailing arguments" do
    code, _out, err = cli("badge", "--history", @history, "stray")
    expect(code).to eq(2)
    expect(err).to eq("saboteur: unexpected arguments: stray\n")
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

  it "badge separates multiple unexpected arguments with spaces in the refusal" do
    code, _out, err = cli("badge", "--history", @history, "stray", "extra")
    expect(code).to eq(2)
    expect(err).to eq("saboteur: unexpected arguments: stray extra\n")
  end

  it "trend separates multiple unexpected arguments with spaces in the refusal" do
    code, _out, err = cli("trend", "--history", @history, "stray", "extra")
    expect(code).to eq(2)
    expect(err).to eq("saboteur: unexpected arguments: stray extra\n")
  end

  it "badge refuses a record with no tested mutants instead of formatting a nil score" do
    append(result_for(:survived))
    previous = history_records.last
    zero_tested = previous.merge(
      "counts" => previous["counts"].transform_values { 0 },
      "breakdown" => previous["breakdown"].merge("score" => nil, "tested" => 0, "assertionKills" => 0,
                                                 "crashKills" => 0, "unclassifiedKills" => 0, "timeouts" => 0,
                                                 "survivors" => 0, "assertionShare" => nil, "crashShare" => nil),
      "score" => 0.0, "coveredScore" => nil, "incomplete" => []
    )
    Saboteur::Reporter::HistoryRecord.validate(zero_tested)
    File.write(@history, "#{JSON.generate(zero_tested)}\n")
    code, _out, err = cli("badge", "--history", @history)
    expect(code).to eq(3)
    expect(err).to include("the latest score history record has no tested mutants")
  end

  it "badge color compares the real percentage against a fractional --high" do
    results = Array.new(4) { result_for(:killed, kill_cause: "assertion") } + [result_for(:survived)]
    append(*results)
    code, out, = cli("badge", "--history", @history, "--high", "80.8")
    expect(code).to eq(0)
    expect(JSON.parse(out).fetch("color")).to eq("yellow")
  end

  it "trend abbreviates the commit to its first 8 characters" do
    append(result_for(:survived))
    record = history_records.last.merge("commit" => "0123456789abcdef0123456789abcdef01234567")
    File.write(@history, "#{JSON.generate(record)}\n")
    code, out, = cli("trend", "--history", @history)
    expect(code).to eq(0)
    expect(out).to include("#{record['date']} 01234567 0.0%\n")
  end
end
