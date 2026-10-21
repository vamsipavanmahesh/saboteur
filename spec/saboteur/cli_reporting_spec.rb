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
      expect(Saboteur::Reporter::Terminal).to receive(:new)
        .with(out, verbose: verbose || false, color: color || :auto, replay_command: kind_of(Proc), all_mutants: false)
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
    arguments = { err: cli.instance_variable_get(:@err), digest: "digest" }
    state = Saboteur::WorkingTree::State.new(head: "a" * 40, dirty: false, changed_files: 0)
    tree = instance_double(Saboteur::WorkingTree, state: state)
    expect(Saboteur::WorkingTree).to receive(:new).with(config.root, ignored: config.output_paths).and_return(tree)
    report = report_of(result_for(:killed))
    engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
    expect(Saboteur::Engine).to receive(:new).with(config, **arguments).and_return(engine)
    expect(cli).to receive(:validate_history).ordered
    expect(cli).to receive(:write_html).with(report).ordered
    expect(cli).to receive(:record_history).with(report).ordered
    expect(cli).to receive(:validate_history).ordered
    expect(cli).to receive(:write_json).with(report, "ok").ordered
    expect(cli.send(:agent_run, arguments)).to eq(0)
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

  [nil, "digest"].each do |digest|
    it "forwards exact engine arguments for replay #{digest.inspect}" do
      err = StringIO.new
      cli = Saboteur::CLI.new([], out: StringIO.new, err: err)
      cli.options[:id] = digest if digest
      arguments = { err: err, verbose: false }
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
end
