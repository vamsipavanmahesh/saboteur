# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "finished run reporting" do
  [[nil, nil, false], [true, :never, true], [false, :always, false]].each do |verbose, color, replay|
    it "passes text choices #{verbose.inspect}/#{color.inspect} and replay=#{replay}" do
      report = report_of(result_for(:killed))
      out = StringIO.new
      err = StringIO.new
      cli = Saboteur::CLI.new([], out: out, err: err)
      cli.instance_variable_set(:@verbose, verbose)
      cli.instance_variable_set(:@color, color)
      cli.options[:id] = "digest" if replay
      terminal = instance_double(Saboteur::Reporter::Terminal)
      expect(cli).to receive(:survivor_replay_command).with(report, nil).and_return(->(digest) { "replay #{digest}" })
      expect(Saboteur::Reporter::Terminal).to receive(:new)
        .with(out, verbose: verbose || false, quiet: false, color: color || :auto, overrides: {},
                   replay_command: kind_of(Proc),
                   all_mutants: false, exit_code: 0, threshold: nil, previous_score: nil, baseline_gate: nil,
                   scope: "whole project")
        .and_return(terminal)
      expect(terminal).to receive(:call).with(report)
      replay_report = instance_double(Saboteur::Reporter::Replay)
      if replay
        expect(Saboteur::Reporter::Replay).to receive(:new).with(out).and_return(replay_report)
        expect(replay_report).to receive(:call).with(report)
      else
        expect(Saboteur::Reporter::Replay).not_to receive(:new)
      end
      expect(cli).to receive(:validate_history).ordered
      expect(cli).to receive(:write_html).with(report).ordered
      expect(cli).to receive(:record_history).with(report).ordered
      expect(cli).to receive(:validate_history).ordered
      expect(cli).to receive(:write_json).with(report, "ok").ordered
      expect(cli.send(:text_run, report, nil)).to eq(0)
      expect(err.string).to eq("\n")
    end
  end

  it "forwards the agent engine config and err stream, preserving provenance output exclusions" do
    cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    config = cli.config
    arguments = { err: cli.instance_variable_get(:@err), digest: "a" * 16 }
    # The machine path is exempt from the noise diet: agent_run forces the quiet start off.
    forwarded = arguments.merge(quiet_start: false)
    state = Saboteur::WorkingTree::State.new(head: "a" * 40, dirty: false, changed_files: 0)
    tree = instance_double(Saboteur::WorkingTree, state: state)
    expect(Saboteur::WorkingTree).to receive(:new).with(config.root, ignored: config.output_paths).and_return(tree)
    report = report_of(result_for(:killed))
    # and_call_original (not and_return) so the forwarded kwargs are executed,
    # not only matched: dropping quiet_start: false must fail this spec.
    expect(Saboteur::Engine).to receive(:new).with(config, **forwarded).and_call_original
    allow_any_instance_of(Saboteur::Engine).to receive(:call).and_return(report)
    expect(cli).to receive(:validate_history).ordered
    expect(cli).to receive(:write_html).with(report).ordered
    expect(cli).to receive(:record_history).with(report).ordered
    expect(cli).to receive(:validate_history).ordered
    expect(cli).to receive(:write_json).with(report, "ok").ordered
    expect(cli.send(:agent_run, arguments)).to eq(0)
  end
  it "wires the replay command through text_run with report first, engine last" do
    report = report_of(result_for(:survived))
    cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    engine = instance_double(Saboteur::Engine, guessed_tests: nil)
    terminal = instance_double(Saboteur::Reporter::Terminal, call: nil)
    captured = nil
    allow(Saboteur::Reporter::Terminal).to receive(:new) do |*_args, **kwargs|
      captured = kwargs[:replay_command]
      terminal
    end
    allow(cli).to receive(:validate_history)
    allow(cli).to receive(:write_html)
    allow(cli).to receive(:record_history)
    allow(cli).to receive(:write_json)
    state = Saboteur::WorkingTree::State.new(head: "a" * 40, dirty: false, changed_files: 0)
    allow(Saboteur::WorkingTree).to receive(:new).and_return(instance_double(Saboteur::WorkingTree, state: state))
    expect(cli.send(:text_run, report, engine)).to eq(1)
    expect(captured.call("53b683c4659bb71c")).to include("saboteur run", "--id", "53b683c4659bb71c")
  end

  {
    "since" => ["origin/main", "--since origin/main"],
    "subjects" => [["Foo#bar"], "--subject Foo#bar"],
    "multi" => [nil, "--subject Foo#bar, Baz.qux"],
    "none" => [nil, "whole project"]
  }.each do |scope, (setting, label)|
    it "labels the clean screen scope as #{label.inspect} (#1173, #1174)" do
      report = report_of(result_for(:killed))
      cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
      if scope == "multi"
        allow(cli.config).to receive(:[]).and_call_original
        allow(cli.config).to receive(:[]).with("subjects").and_return(["Foo#bar", "Baz.qux"])
      elsif scope != "none"
        allow(cli.config).to receive(:[]).and_call_original
        allow(cli.config).to receive(:[]).with(scope).and_return(setting)
      end
      captured = nil
      allow(Saboteur::Reporter::Terminal).to receive(:new) do |*_args, **kwargs|
        captured = kwargs[:scope]
        instance_double(Saboteur::Reporter::Terminal, call: nil)
      end
      allow(cli).to receive(:validate_history)
      allow(cli).to receive(:write_html)
      allow(cli).to receive(:record_history)
      allow(cli).to receive(:write_json)
      state = Saboteur::WorkingTree::State.new(head: "a" * 40, dirty: false, changed_files: 0)
      allow(Saboteur::WorkingTree).to receive(:new).and_return(instance_double(Saboteur::WorkingTree, state: state))
      cli.send(:text_run, report, nil)
      expect(captured).to eq(label)
    end
  end

  it "labels the clean screen scope with positional sources (#1174)" do
    report = report_of(result_for(:killed))
    cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    cli.instance_variable_set(:@sources, ["lib/foo.rb", "lib/bar.rb"])
    captured = nil
    allow(Saboteur::Reporter::Terminal).to receive(:new) do |*_args, **kwargs|
      captured = kwargs[:scope]
      instance_double(Saboteur::Reporter::Terminal, call: nil)
    end
    allow(cli).to receive(:validate_history)
    allow(cli).to receive(:write_html)
    allow(cli).to receive(:record_history)
    allow(cli).to receive(:write_json)
    state = Saboteur::WorkingTree::State.new(head: "a" * 40, dirty: false, changed_files: 0)
    allow(Saboteur::WorkingTree).to receive(:new).and_return(instance_double(Saboteur::WorkingTree, state: state))
    cli.send(:text_run, report, nil)
    expect(captured).to eq("lib/foo.rb, lib/bar.rb")
  end

  it "builds survivor replay commands from a working tree that excludes output paths" do
    cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    config = cli.config
    state = Saboteur::WorkingTree::State.new(head: "a" * 40, dirty: false, changed_files: 0)
    tree = instance_double(Saboteur::WorkingTree, state: state)
    expect(Saboteur::WorkingTree).to receive(:new).with(config.root, ignored: config.output_paths).and_return(tree)
    engine = instance_double(Saboteur::Engine, guessed_tests: nil)
    command = cli.send(:survivor_replay_command, report_of(result_for(:survived)), engine).call("53b683c4659bb71c")
    expect(command).to include("saboteur run", "--id", "53b683c4659bb71c")
  end

  it "narrows the run screen's replay command to the covering spec files (#1148)" do
    cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    state = Saboteur::WorkingTree::State.new(head: "a" * 40, dirty: false, changed_files: 0)
    tree = instance_double(Saboteur::WorkingTree, state: state)
    allow(Saboteur::WorkingTree).to receive(:new).and_return(tree)
    engine = instance_double(Saboteur::Engine, guessed_tests: %w[spec/a_spec.rb spec/b_spec.rb])
    survivor = result_for(:survived, covered_by: ["./spec/person_spec.rb[1:3]"])
    command = cli.send(:survivor_replay_command, report_of(survivor), engine).call(survivor.digest)
    words = Shellwords.split(command)
    expect(words.each_cons(2).to_a).to include(["--test", "spec/person_spec.rb"])
    expect(words).not_to include("spec/a_spec.rb", "spec/b_spec.rb")
  end

  [nil, "digest"].each do |digest|
    it "forwards exact engine arguments for replay #{digest.inspect}" do
      err = StringIO.new
      cli = Saboteur::CLI.new([], out: StringIO.new, err: err)
      cli.options[:id] = digest if digest
      arguments = { err: err, verbose: false, palette: kind_of(Saboteur::Reporter::Palette) }
      arguments[:digest] = digest if digest
      report = report_of(result_for(:killed))
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      expect(Saboteur::Engine).to receive(:new).with(cli.config, **arguments).and_return(engine)
      expect(cli).to receive(:text_run).with(report, engine).and_return(0)
      expect(cli.send(:execute_run)).to eq(0)
    end
  end

  it "verifies path identities before reading history" do
    cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    config = Saboteur::Config.new({ "score_history" => "out/history.jsonl" })
    allow(cli).to receive(:config).and_return(config)
    history = instance_double(Saboteur::Reporter::ScoreHistory)
    paths = %w[score_history json_report html_report].map { |key| config.path(key) }
    expect(Saboteur::Reporter::HistoryPaths).to receive(:validate).with(paths).ordered
    expect(Saboteur::Reporter::ScoreHistory).to receive(:new).with(config.path("score_history")).and_return(history)
    expect(history).to receive(:validate_existing)
    cli.send(:validate_history)
  end
  it "reads the previous covered score from the history, tolerating its absence" do
    cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    expect(cli.send(:previous_score)).to be_nil

    config = Saboteur::Config.new({ "score_history" => "out/history.jsonl" })
    allow(cli).to receive(:config).and_return(config)
    reads = []
    allow(Saboteur::Reporter::HistoryReader).to receive(:read) { |path| reads << path }
    expect(cli.send(:previous_score)).to be_nil
    expect(reads).to eq([])

    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(config.path("score_history")).and_return(true)
    reader = Saboteur::Reporter::HistoryReader
    history_path = config.path("score_history")
    allow(reader).to receive(:read).with(history_path).and_return([])
    expect(cli.send(:previous_score)).to be_nil
    allow(reader).to receive(:read).with(history_path).and_return([{ "coveredTime" => 1 }])
    expect(cli.send(:previous_score)).to be_nil
    allow(reader).to receive(:read).with(history_path).and_return([{ "coveredScore" => 0.5 },
                                                                   { "coveredScore" => 0.732 }])
    expect(cli.send(:previous_score)).to eq(0.732)
    allow(reader).to receive(:read).with(history_path).and_raise(Saboteur::Error, "corrupt")
    expect(cli.send(:previous_score)).to be_nil
  end
end
