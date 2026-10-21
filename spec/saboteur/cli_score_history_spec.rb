# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "score history CLI" do
  it "records text and agent runs without contaminating agent stdout" do
    Dir.mktmpdir(nil, File.realpath(Dir.tmpdir)) do |dir|
      [[], ["--agent"]].each_with_index do |format, index|
        out = StringIO.new
        err = StringIO.new
        report = report_of(result_for(:killed))
        engine = engine_double(guessed_tests: nil, call: report)
        allow(Saboteur::Engine).to receive(:new).and_return(engine)
        allow_any_instance_of(Saboteur::CLI).to receive(:write_html)
        allow_any_instance_of(Saboteur::CLI).to receive(:write_json)
        path = File.join(dir, "#{index}.jsonl")
        cli = Saboteur::CLI.new(["run", *format, "--score-history", path], out: out, err: err)
        expect(cli.call).to eq(0)
        expect(JSON.parse(File.read(path)).fetch("coveredScore")).to eq(1.0)
        expect(err.string).to include("score history: first record")
        expect(JSON.parse(out.string).fetch("verdict")).to eq("clean") if format.any?
      end
    end
  end

  it "parses the history destination and describes the opt-in JSONL switch" do
    cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    parser = cli.parser
    parser.parse!(%w[--score-history out/history.jsonl])
    expect(cli.options[:score_history]).to eq("out/history.jsonl")
    expect(parser.to_s).to include("--score-history PATH", "Append score history JSONL (opt-in)")
  end

  it "rejects colliding output destinations" do
    expect { Saboteur::Config.new({ "score_history" => ".saboteur/report.json" }) }
      .to raise_error(Saboteur::ConfigError, /distinct paths/)
  end
  it "does not create a history file for previews or failed engine runs" do
    Dir.mktmpdir(nil, File.realpath(Dir.tmpdir)) do |dir|
      path = File.join(dir, "history.jsonl")
      out = StringIO.new
      err = StringIO.new
      preview = Saboteur::CLI.new(["run", "--list-operators", "--score-history", path], out: out, err: err)
      expect(preview.call).to eq(0)
      expect(File).not_to exist(path)
      allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "boot failed")
      failure = Saboteur::CLI.new(["run", "--score-history", path], out: out, err: err)
      expect(failure.call).to eq(3)
      expect(File).not_to exist(path)
    end
  end
  it "passes exact selection and commit without output paths and ignores the history file" do
    command = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    config = Saboteur::Config.new({ "score_history" => "out/history.jsonl" })
    allow(command).to receive(:config).and_return(config)
    state = Saboteur::WorkingTree::State.new(head: "a" * 40, dirty: false, changed_files: 0)
    tree = instance_double(Saboteur::WorkingTree, state: state)
    expect(Saboteur::WorkingTree).to receive(:new).with(config.root, ignored: config.output_paths).and_return(tree)
    expect(config.output_paths).to include("out/history.jsonl")
    history = instance_double(Saboteur::Reporter::ScoreHistory)
    expect(Saboteur::Reporter::ScoreHistory).to receive(:new).with(config.path("score_history")).and_return(history)
    report = report_of(result_for(:killed))
    expected = config.selection_settings.except("json_report", "html_report", "score_history", "cache_dir", "resume",
                                                "palette")
    expect(history).to receive(:append).with(report, head: "a" * 40, scope: expected).and_return("recorded")
    command.send(:record_history, report)
  end

  it "does not split the history scope by the resume directory (#471)" do
    command = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    config = Saboteur::Config.new({ "score_history" => "out/history.jsonl", "resume" => "state/run1" })
    allow(command).to receive(:config).and_return(config)
    state = Saboteur::WorkingTree::State.new(head: "a" * 40, dirty: false, changed_files: 0)
    allow(Saboteur::WorkingTree).to receive(:new).and_return(instance_double(Saboteur::WorkingTree, state: state))
    history = instance_double(Saboteur::Reporter::ScoreHistory)
    allow(Saboteur::Reporter::ScoreHistory).to receive(:new).and_return(history)
    allow(history).to receive(:append).and_return("recorded")
    command.send(:record_history, report_of(result_for(:killed)))
    expect(history).to have_received(:append).with(anything, head: "a" * 40,
                                                             scope: hash_excluding("resume", "cache_dir"))
  end

  it "does not ask for a history writer unless explicitly enabled" do
    command = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    expect(Saboteur::Reporter::ScoreHistory).not_to receive(:new)
    command.send(:record_history, report_of(result_for(:killed)))
  end
end
