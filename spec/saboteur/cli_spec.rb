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
      expect(err.string).not_to include("incomplete")
    end

    it "is 0 when the score is above --threshold, and 1 just above a score of 50 %" do
      report = report_of(result_for(:killed), result_for(:survived))
      engine = instance_double(Saboteur::Engine, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      json = File.join(Dir.mktmpdir, "r.json")
      expect(cli("run", "--threshold", "40", "--json", json).call).to eq(0)
      expect(cli("run", "--threshold", "50.3", "--json", json).call).to eq(1)
    end

    it "is 1 under --threshold when nothing was tested, and says why" do
      engine = instance_double(Saboteur::Engine, call: report_of(result_for(:skipped, reason: "no coverage")))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "0", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(1)
      expect(err.string).to include("no mutant was tested, so there is no score")
    end

    it "is 1 under --threshold for a run with no mutants at all" do
      engine = instance_double(Saboteur::Engine, call: report_of)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "90", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(1)
    end

    it "is 3 under --threshold when some mutants errored, even with a passing score" do
      report = report_of(result_for(:killed), result_for(:error))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
      expect(cli("run", "--threshold", "50", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(3)
      expect(err.string).to include("1 mutant(s) errored or hit a resource limit, so the score is incomplete")
    end

    it "is 3 under --threshold when a mutant hit a resource limit" do
      report = report_of(result_for(:killed), result_for(:resource_limit))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
      expect(cli("run", "--threshold", "50", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(3)
    end

    it "ignores errors for the exit code when no threshold is set" do
      report = report_of(result_for(:killed), result_for(:error))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
      expect(cli("run", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
    end

    it "keeps exit 3 over the threshold when every executed mutant errored" do
      engine = instance_double(Saboteur::Engine, call: report_of(result_for(:error)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "0", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(3)
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

  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p(%w[lib/sub spec])
        %w[lib/a.rb lib/b.rb spec/a_spec.rb spec/b_spec.rb].each { |file| FileUtils.touch(file) }
        FileUtils.touch("lib/notes.txt")
        example.run
      end
    end
  end

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

  it "turns a source directory into a pattern over its Ruby files" do
    command = cli("run", "lib/sub/", "lib")
    command.call
    expect(command.options[:include]).to eq(%w[lib/sub/**/*.rb lib/**/*.rb])
  end

  it "escapes glob characters in a literal source file or directory" do
    FileUtils.mkdir_p("src[1]")
    FileUtils.touch(["lib/a[1].rb", "lib/a{x}.rb", "src[1]/c.rb"])
    command = cli("run", "lib/a[1].rb", "lib/a{x}.rb", "src[1]")
    command.call
    expect(command.options[:include]).to eq(['lib/a\\[1\\].rb', 'lib/a\\{x\\}.rb', 'src\\[1\\]/**/*.rb'])
    config = Saboteur::Config.new({ "include" => command.options[:include] }, root: Dir.pwd)
    expect(config.included_files.map { |file| file.delete_prefix("#{File.realpath(Dir.pwd)}/") })
      .to eq(["lib/a[1].rb", "lib/a{x}.rb", "src[1]/c.rb"])
  end

  it "accepts a test with comma-separated ids in one selector" do
    command = cli("run", "lib/a.rb", "--test", "spec/a_spec.rb[1:1,1:2]", "--test", "spec/b_spec.rb:3:9")
    expect(command.call).to eq(3)
    expect(command.options[:tests]).to eq(%w[spec/a_spec.rb[1:1,1:2] spec/b_spec.rb:3:9])
  end

  it "accepts a test with a line or id selector when its file exists" do
    command = cli("run", "lib/a.rb", "--test", "spec/a_spec.rb:12", "--test", "spec/b_spec.rb[1:2]")
    expect(command.call).to eq(3)
    expect(command.options[:tests]).to eq(%w[spec/a_spec.rb:12 spec/b_spec.rb[1:2]])
  end

  it "refuses --test without a source, with exit 2" do
    expect(cli("run", "--test", "spec/a_spec.rb").call).to eq(2)
    expect(err.string).to include("--test needs at least one source file")
  end

  it "refuses a source that does not exist, with exit 2 and no run" do
    expect(cli("run", "lib/typo.rb").call).to eq(2)
    expect(err.string).to include("source file not found: lib/typo.rb")
    expect(Saboteur::Engine).not_to have_received(:new)
  end

  it "refuses a source that is not a Ruby file" do
    expect(cli("run", "lib/notes.txt").call).to eq(2)
    expect(err.string).to include("source is not a Ruby file: lib/notes.txt")
  end

  it "reports a missing non-Ruby source as not found" do
    expect(cli("run", "lib/missing.txt").call).to eq(2)
    expect(err.string).to include("source file not found: lib/missing.txt")
  end

  it "refuses a test file that does not exist" do
    expect(cli("run", "lib/a.rb", "--test", "spec/typo_spec.rb:3").call).to eq(2)
    expect(err.string).to include("test file not found: spec/typo_spec.rb:3")
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
