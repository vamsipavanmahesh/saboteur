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

  describe "dirty working tree" do
    def run_on_tree(state)
      tree = instance_double(Saboteur::WorkingTree, state: state)
      allow(Saboteur::WorkingTree).to receive(:new).and_return(tree)
      allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
      cli("run").call
    end

    it "refuses --agent and --id with --dry-run or --list-operators as usage errors" do
      [%w[--dry-run --agent], %w[--list-operators --agent], %w[--dry-run --id abc], %w[--list-operators --id abc]]
        .each do |args|
        expect(Saboteur::Preview).not_to receive(:new)
        out.truncate(0)
        expect(cli("run", *args).call).to eq(2)
      end
      expect(err.string).to include("--id replays one mutant: not with --dry-run or --list-operators",
                                    "--dry-run and --list-operators print text, not --agent JSON")
    end

    it "warns at startup with the number of uncommitted changes" do
      run_on_tree(Saboteur::WorkingTree::State.new(head: "abc", dirty: true, changed_files: 3))

      expect(err.string).to include("saboteur: warning: 3 uncommitted change(s) in the working tree")
      expect(err.string).to include("clean, committed tree or a CI checkout")
    end

    it "excludes saboteur's own output paths from the changes it counts" do
      run_on_tree(Saboteur::WorkingTree::State.new(head: "abc", dirty: true, changed_files: 1))

      expect(Saboteur::WorkingTree).to have_received(:new)
        .with(anything, ignored: [".saboteur", ".saboteur/report.json", ".saboteur/report.html"])
    end

    it "stays quiet on a clean tree" do
      run_on_tree(Saboteur::WorkingTree::State.new(head: "abc", dirty: false, changed_files: 0))

      expect(err.string).not_to include("uncommitted")
      expect(err.string).not_to match(/\A\s*\n/)
    end

    it "stays quiet when the tree state is unknown" do
      run_on_tree(Saboteur::WorkingTree::UNKNOWN)

      expect(err.string).not_to include("uncommitted")
    end
  end

  describe "exit codes after a run" do
    def run_with(report)
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
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
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "60", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(1)
    end

    it "is 0 when the score meets --threshold exactly, despite survivors" do
      report = report_of(result_for(:killed), result_for(:survived))
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "50", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
      expect(err.string).not_to include("incomplete")
    end

    it "is 0 when the score is above --threshold, and 1 just above a score of 50 %" do
      report = report_of(result_for(:killed), result_for(:survived))
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      json = File.join(Dir.mktmpdir, "r.json")
      expect(cli("run", "--threshold", "40", "--json", json).call).to eq(0)
      expect(cli("run", "--threshold", "50.3", "--json", json).call).to eq(1)
    end

    it "is 1 under --threshold when nothing was tested, and says why" do
      engine = instance_double(Saboteur::Engine, guessed_tests: nil,
                                                 call: report_of(result_for(:skipped, reason: "no coverage")))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "0", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(1)
      expect(err.string).to include("no mutant was tested, so there is no score")
    end

    it "is 1 under --threshold for a run with no mutants at all" do
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "90", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(1)
    end

    it "is 3 under --threshold when some mutants errored, even with a passing score" do
      report = report_of(result_for(:killed), result_for(:error))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, guessed_tests: nil,
                                                                                            call: report))
      expect(cli("run", "--threshold", "50", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(3)
      expect(err.string).to include("1 mutant(s) errored or hit a resource limit, so the score is incomplete")
    end

    it "is 3 under --threshold when a mutant hit a resource limit" do
      report = report_of(result_for(:killed), result_for(:resource_limit))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, guessed_tests: nil,
                                                                                            call: report))
      expect(cli("run", "--threshold", "50", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(3)
    end

    it "ignores errors for the exit code when no threshold is set" do
      report = report_of(result_for(:killed), result_for(:error))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, guessed_tests: nil,
                                                                                            call: report))
      expect(cli("run", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
    end

    it "keeps exit 3 over the threshold when every executed mutant errored" do
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:error)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "0", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(3)
    end

    it "is 3 when every executed mutant errored" do
      expect(run_with(report_of(result_for(:error), result_for(:skipped, reason: "no coverage")))).to eq(3)
    end

    # Errored mutants are outside the score, so a mostly-errored run tested
    # almost nothing; it must not go green even without a threshold.
    it "is 3 when most executed mutants errored, and says why" do
      report = report_of(result_for(:killed), result_for(:error), result_for(:error))
      expect(run_with(report)).to eq(3)
      expect(err.string).to include("2 of 3 mutants errored")
    end

    it "still passes when at most half of the executed mutants errored" do
      report = report_of(result_for(:killed), result_for(:error))
      expect(run_with(report)).to eq(0)
    end

    # Skipped mutants never ran, so they are neither numerator nor
    # denominator: 2 errors of 3 executed is a majority even with skips.
    it "does not let skipped mutants dilute the error fraction" do
      report = report_of(result_for(:killed), result_for(:error), result_for(:error),
                         result_for(:skipped, reason: "no coverage"), result_for(:skipped, reason: "no coverage"))
      expect(run_with(report)).to eq(3)
      expect(err.string).to include("2 of 3 mutants errored")
    end

    # The majority rule fires before the survivor gate: a run that tested
    # almost nothing fails as a tool error, not as survivors.
    it "is 3, not 1, with survivors when most executed mutants errored" do
      report = report_of(result_for(:survived), result_for(:error), result_for(:error), result_for(:error))
      expect(run_with(report)).to eq(3)
    end

    it "writes the majority-error cause into the JSON report" do
      report = report_of(result_for(:killed), result_for(:error), result_for(:error))
      json = File.join(Dir.mktmpdir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--json", json).call).to eq(3)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("errorMajority")
    end

    # A fresh majority JSON plus a failing later stage used to pass the
    # harness's acceptance: the report is the completion evidence, so it
    # must not exist when reporting did not complete.
    it "writes no JSON report when a later reporting stage fails" do
      report = report_of(result_for(:killed), result_for(:error), result_for(:error))
      dir = Dir.mktmpdir
      json = File.join(dir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow_any_instance_of(Saboteur::Reporter::Html).to receive(:call).and_raise(Saboteur::Error, "no html")
      expect(cli("run", "--json", json, "--html", File.join(dir, "r.html")).call).to eq(3)
      expect(File).not_to exist(json)
    end

    # Agent mode shares the publish rule: the payload build and render are
    # fallible stages too, so the JSON is written only after them.
    it "gives agent provenance the specs --guess-tests narrowed to, not the original --test list" do
      report = report_of(result_for(:killed))
      engine = instance_double(Saboteur::Engine, guessed_tests: %w[spec/a_spec.rb], call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow(Saboteur::Reporter::Agent).to receive(:call).and_call_original
      cli("run", "--agent", "--since", "HEAD", "--guess-tests").call
      expect(Saboteur::Reporter::Agent).to have_received(:call) do |_report, provenance|
        expect(provenance.tests).to eq(%w[spec/a_spec.rb])
      end
    end

    it "keeps the explicit --test list in agent provenance when nothing was guessed" do
      spec = File.join(Dir.mktmpdir, "x_spec.rb")
      File.write(spec, "")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:killed)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow(Saboteur::Reporter::Agent).to receive(:call).and_call_original
      source = File.join(File.dirname(spec), "x.rb")
      File.write(source, "")
      cli("run", "--agent", "--test", spec, source).call
      expect(Saboteur::Engine).to have_received(:new).with(be_a(Saboteur::Config), any_args)
      expect(Saboteur::Reporter::Agent).to have_received(:call) do |_report, provenance|
        expect(provenance.tests).to eq([spec])
      end
    end

    it "writes no JSON report in agent mode when the payload build fails" do
      report = report_of(result_for(:killed), result_for(:error), result_for(:error))
      dir = Dir.mktmpdir
      json = File.join(dir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow(Saboteur::Reporter::Agent).to receive(:call).and_raise(Saboteur::Error, "no payload")
      expect(cli("run", "--agent", "--json", json).call).to eq(3)
      expect(File).not_to exist(json)
    end

    # The recorded cause is the agent-mode classification: survivors exit 1
    # even when most mutants errored, and the JSON must say the same.
    it "records survivors as the cause in agent mode when survivors gate the exit" do
      report = report_of(result_for(:survived), result_for(:error), result_for(:error), result_for(:error))
      json = File.join(Dir.mktmpdir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--agent", "--json", json).call).to eq(1)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("survivors")
    end

    it "records the majority-error cause in agent mode when it decides the exit" do
      report = report_of(result_for(:killed), result_for(:error), result_for(:error))
      json = File.join(Dir.mktmpdir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--agent", "--json", json).call).to eq(3)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("errorMajority")
    end

    it "records an incomplete cause in agent mode when a minority errored" do
      report = report_of(result_for(:killed), result_for(:error))
      json = File.join(Dir.mktmpdir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--agent", "--json", json).call).to eq(3)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("incomplete")
    end

    # Agent mode prints exactly one payload on stdout: any announcement or
    # a missing print breaks the parse, and the reports it names exist.
    it "prints only the payload and writes both reports in agent mode" do
      report = report_of(result_for(:killed))
      dir = Dir.mktmpdir
      json = File.join(dir, "r.json")
      html = File.join(dir, "r.html")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--agent", "--json", json, "--html", html).call).to eq(0)
      expect(JSON.parse(out.string)["status"]).to eq("complete")
      expect(File).to exist(json)
      expect(File.read(html)).to start_with("<!DOCTYPE html>")
    end

    it "records ok as the cause in agent mode when the run is clean" do
      report = report_of(result_for(:killed))
      json = File.join(Dir.mktmpdir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--agent", "--json", json).call).to eq(0)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("ok")
    end

    it "writes ok into the JSON report when nothing failed" do
      json = File.join(Dir.mktmpdir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:killed)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--json", json).call).to eq(0)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("ok")
    end

    it "writes survivors into the JSON report when the survivor gate fails" do
      json = File.join(Dir.mktmpdir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:survived)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--json", json).call).to eq(1)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("survivors")
    end

    it "writes belowThreshold into the JSON report when the score misses the threshold" do
      json = File.join(Dir.mktmpdir, "r.json")
      report = report_of(result_for(:killed), result_for(:survived))
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "90", "--json", json).call).to eq(1)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("belowThreshold")
    end

    it "writes the incomplete-under-threshold cause into the JSON report" do
      report = report_of(result_for(:killed), result_for(:error))
      json = File.join(Dir.mktmpdir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      expect(cli("run", "--threshold", "50", "--json", json).call).to eq(3)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("incompleteUnderThreshold")
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

  it "parses --allow-focus into the allow_focus config key" do
    command = cli("run", "--allow-focus")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(allow_focus: true)
    expect(Saboteur::Config.new(command.options.transform_keys(&:to_s))["allow_focus"]).to be(true)
  end

  it "refuses a focused suite unless allow_focus is set" do
    expect(Saboteur::Config.new({})["allow_focus"]).to be(false)
  end

  it "parses --config, --integration and --incremental" do
    command = cli("run", "--config", "x.yml", "--integration", "rspec", "--incremental")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    allow(Saboteur::Config).to receive(:load).and_call_original
    command.call
    expect(command.options).to include(config: "x.yml", integration: "rspec", incremental: true)
    expect(Saboteur::Config).to have_received(:load).with(hash_including(path: "x.yml"))
  end

  it "parses --no-guess-tests so a frozen --test command can override guess_tests in the config file" do
    command = cli("run", "--since", "main", "--no-guess-tests")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(guess_tests: false)
  end

  it "parses --guess-tests" do
    command = cli("run", "--since", "main", "--guess-tests")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(guess_tests: true)
  end

  it "describes --config with its default in both parsers" do
    cli = cli("run")
    [cli.parser, cli.doctor_parser].each do |parser|
      config_switch = parser.top.list.find { |switch| switch.long.include?("--config") }
      expect(config_switch.desc).to include("Config file (default config/saboteur.rb)")
    end
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
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "saboteur.rb"), "Saboteur.configure { |c| c.html_report = nil }\n")
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
      .and_return(instance_double(Saboteur::Engine, guessed_tests: nil,
                                                    call: report_of(result_for(:skipped, reason: "no coverage"))))
    expect(cli("run", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
  end

  describe "help" do
    it "prints the full map for help, --help and -h, to stdout, and exits 0" do
      [%w[help], %w[--help], %w[-h]].each do |argv|
        output = StringIO.new
        error = StringIO.new
        expect(described_class.new(argv, out: output, err: error).call).to eq(0)
        expect(output.string).to include("COMMANDS").and include("--since REF")
        expect(error.string).to be_empty
      end
    end

    it "prints details for one command with help <command> and <command> --help" do
      [%w[help run], %w[run --help], %w[run -h]].each do |argv|
        output = StringIO.new
        expect(described_class.new(argv, out: output, err: err).call).to eq(0)
        expect(output.string).to start_with("saboteur run - ")
      end
    end

    it "does not run mutation testing when help is asked for" do
      allow(Saboteur::Engine).to receive(:new)
      cli("run", "--help").call
      expect(Saboteur::Engine).not_to have_received(:new)
    end

    it "exits 2 and names the real commands for help about an unknown command" do
      expect(cli("help", "explode").call).to eq(2)
      names = Saboteur::Help::COMMANDS.map(&:name).join(", ")
      expect(err.string).to include("unknown command: explode").and include(names)
    end

    it "shows doctor's own help without running it" do
      allow(Saboteur::Doctor).to receive(:new)
      expect(cli("doctor", "--help").call).to eq(0)
      expect(out.string).to include("saboteur doctor - ").and include("--seed N")
      expect(Saboteur::Doctor).not_to have_received(:new)
    end

    it "points to help from the usage text" do
      expect(described_class::USAGE).to include("saboteur help")
    end
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

  # A pull-request run: --since already names the sources (the changed
  # files), so listing them again only repeats the diff.
  it "accepts --test without a source when --since scopes the run" do
    command = cli("run", "--since", "origin/main", "--test", "spec/a_spec.rb")
    expect(command.call).to eq(3)
    expect(command.options[:tests]).to eq(%w[spec/a_spec.rb])
    expect(command.options[:include]).to be_nil
  end

  it "accepts --test without a source when since comes from the config file" do
    FileUtils.mkdir_p("config")
    File.write("config/saboteur.rb", "Saboteur.configure { |c| c.since = \"origin/main\" }\n")
    command = cli("run", "--test", "spec/a_spec.rb")
    expect(command.call).to eq(3)
    expect(command.options[:tests]).to eq(%w[spec/a_spec.rb])
  end

  it "still refuses a missing test file when --since scopes the run" do
    expect(cli("run", "--since", "origin/main", "--test", "spec/nope_spec.rb").call).to eq(2)
    expect(err.string).to include("test file not found: spec/nope_spec.rb")
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

RSpec.describe Saboteur::CLI, "--allow-hazardous (issue #102)" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    described_class.new(argv, out:, err:)
  end

  it "parses into the config overrides" do
    command = cli("run", "--allow-hazardous")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to eq(allow_hazardous: true)
  end
end
