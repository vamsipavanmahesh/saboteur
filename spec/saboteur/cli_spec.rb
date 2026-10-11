# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    described_class.new(argv, out:, err:)
  end

  it "prints the version" do
    expect(cli("version").call).to eq(0)
    expect(out.string.strip).to eq(Saboteur::VERSION)
  end

  it "parses run options into config overrides" do
    command = cli("run", "--since", "main", "--subject", "A#b", "--subject", "C.d",
                  "--timeout-factor", "2.5", "--jobs", "1", "--reeval", "nesting", "--no-cache", "--seed", "42")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to eq(since: "main", subjects: ["A#b", "C.d"], timeout_factor: 2.5, jobs: 1,
                                  reeval: "nesting", cache: false, seed: 42)
  end

  it "exits 2 for config errors, without starting a run" do
    allow(Saboteur::Engine).to receive(:new)
    expect(cli("run", "--jobs", "0").call).to eq(2)
    expect(err.string).to include("jobs must be >= 1")
    expect(Saboteur::Engine).not_to have_received(:new)
  end

  it "exits 3 for tool errors" do
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "boot failed")
    expect(cli("run").call).to eq(3)
    expect(err.string).to include("saboteur: boot failed")
  end

  it "prints usage and exits 2 for an unknown command" do
    expect(cli("explode").call).to eq(2)
    expect(err.string).to include("Usage: saboteur run")
  end

  it "prints usage and exits 2 for a bad option" do
    expect(cli("run", "--jobs", "many").call).to eq(2)
    expect(err.string).to include("invalid argument")
  end

  describe "exit codes after a run" do
    def run_with(report)
      engine = instance_double(Saboteur::Engine, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      cli("run", "--json", File.join(Dir.mktmpdir, "r.json")).call
    end

    it "is 0 with no survivors" do
      expect(run_with(report_of(result_for(:killed)))).to eq(0)
    end

    it "is 1 with an unignored survivor" do
      expect(run_with(report_of(result_for(:survived)))).to eq(1)
    end

    it "is 0 when every survivor is ignored" do
      survivor = result_for(:survived)
      survivor.ignored = "equivalent"
      expect(run_with(report_of(survivor))).to eq(0)
    end

    it "is 1 when the score is below --threshold, even with ignored survivors" do
      report = report_of(result_for(:killed), result_for(:survived))
      engine = instance_double(Saboteur::Engine, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "60", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(1)
    end

    it "is 0 when the score meets --threshold exactly, despite survivors" do
      report = report_of(result_for(:killed), result_for(:survived))
      engine = instance_double(Saboteur::Engine, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "50", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
    end

    it "is 0 when the score is above --threshold, and 1 just above a score of 50 %" do
      report = report_of(result_for(:killed), result_for(:survived))
      engine = instance_double(Saboteur::Engine, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      json = File.join(Dir.mktmpdir, "r.json")
      expect(cli("run", "--threshold", "40", "--json", json).call).to eq(0)
      expect(cli("run", "--threshold", "50.3", "--json", json).call).to eq(1)
    end

    it "is 0 under --threshold when nothing was tested" do
      engine = instance_double(Saboteur::Engine, call: report_of(result_for(:skipped, reason: "no coverage")))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "90", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
    end

    it "is 3 when every executed mutant errored" do
      expect(run_with(report_of(result_for(:error), result_for(:skipped, reason: "no coverage")))).to eq(3)
    end
  end
end

RSpec.describe Saboteur::CLI, "details" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    described_class.new(argv, out:, err:)
  end

  it "prints only the usage line for an unknown command" do
    cli("explode").call
    expect(err.string).to eq("#{described_class::USAGE}\n")
  end

  it "parses --config, --integration and --incremental" do
    command = cli("run", "--config", "x.yml", "--integration", "rspec", "--incremental")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    allow(Saboteur::Config).to receive(:load).and_call_original
    command.call
    expect(command.options).to include(config: "x.yml", integration: "rspec", incremental: true)
    expect(Saboteur::Config).to have_received(:load).with(hash_including(path: "x.yml"))
  end

  it "prints the summary and writes the JSON report it names" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "r.json")
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine,
                                                                          call: report_of(result_for(:killed))))
      cli("run", "--json", path).call
      expect(out.string).to include("saboteur #{Saboteur::VERSION}:", "JSON report: #{path}")
      expect(File).to exist(path)
    end
  end

  it "writes the HTML report it names, next to the JSON one" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "r.html")
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine,
                                                                          call: report_of(result_for(:killed))))
      cli("run", "--json", File.join(dir, "r.json"), "--html", path).call
      expect(out.string).to include("HTML report: #{path}")
      expect(File.read(path)).to start_with("<!DOCTYPE html>")
    end
  end

  it "writes no HTML report when html_report is null in the config" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".saboteur.yml"), "html_report: null\n")
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine,
                                                                          call: report_of(result_for(:killed))))
      Dir.chdir(dir) { cli("run").call }
      expect(out.string).not_to include("HTML report:")
      expect(Dir.glob("#{dir}/**/*.html")).to be_empty
    end
  end

  it "refuses to run when the JSON and HTML reports share one path" do
    allow(Saboteur::Engine).to receive(:new)
    expect(cli("run", "--json", "same.out", "--html", "same.out").call).to eq(2)
    expect(err.string).to include("json_report and html_report both point to")
    expect(Saboteur::Engine).not_to have_received(:new)
  end

  it "refuses to run when the default JSON path is also the HTML path" do
    allow(Saboteur::Engine).to receive(:new)
    expect(cli("run", "--html", ".saboteur/report.json").call).to eq(2)
    expect(Saboteur::Engine).not_to have_received(:new)
  end

  it "exits 0 when every mutant was skipped (nothing ran, nothing errored)" do
    allow(Saboteur::Engine).to receive(:new)
      .and_return(instance_double(Saboteur::Engine, call: report_of(result_for(:skipped, reason: "no coverage"))))
    expect(cli("run", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
  end
end

RSpec.describe Saboteur::CLI, "explicit files" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    described_class.new(argv, out:, err:)
  end

  before { allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop") }

  it "takes positional sources as the files to mutate, replacing include and exclude" do
    command = cli("run", "lib/a.rb", "lib/b.rb", "--test", "spec/a_spec.rb", "--test", "spec/b_spec.rb")
    expect(command.call).to eq(3)
    expect(command.options).to eq(include: %w[lib/a.rb lib/b.rb], exclude: [],
                                  tests: %w[spec/a_spec.rb spec/b_spec.rb])
  end

  it "refuses --test without a source, with exit 2" do
    expect(cli("run", "--test", "spec/a_spec.rb").call).to eq(2)
    expect(err.string).to include("--test needs at least one source file")
  end

  it "parses --threshold as a number" do
    command = cli("run", "--threshold", "92.5")
    command.call
    expect(command.options).to eq(threshold: 92.5)
  end

  it "rejects a --threshold outside 0 to 100 with exit 2" do
    expect(cli("run", "--threshold", "101").call).to eq(2)
    expect(err.string).to include("threshold must be between 0 and 100")
  end
end
