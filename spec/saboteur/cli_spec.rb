# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "stringio"
require "tmpdir"

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

  # B3: an unexpected failure must not escape as a bare stack trace and
  # an accidental exit 1; it is reported as ours and exits 3.
  it "reports an unexpected failure as an internal error and exits 3" do
    allow(Saboteur::Engine).to receive(:new).and_raise(NoMethodError, "undefined method `boom'")
    expect(cli("run").call).to eq(3)
    expect(err.string).to include("saboteur: internal error (NoMethodError: undefined method `boom'")
    expect(err.string).to include("please report it: https://github.com/vamsipavanmahesh/saboteur/issues")
  end

  it "collapses a multiline crash message into the one-line diagnostic" do
    allow(Saboteur::Engine).to receive(:new).and_raise(RuntimeError, "first line\nsecond line")
    expect(cli("run").call).to eq(3)
    expect(err.string).to include("internal error (RuntimeError: first line second line)")
    expect(err.string).not_to include("second line\n")
  end

  it "scrubs locale-invalid bytes out of a crash message" do
    allow(Saboteur::Engine).to receive(:new)
      .and_raise(RuntimeError, "broken \xFF byte".dup.force_encoding(Encoding::UTF_8))
    expect(cli("run").call).to eq(3)
    expect(err.string).to include("internal error (RuntimeError: broken ? byte)")
  end

  it "leaves a crash message at the length cap untouched" do
    allow(Saboteur::Engine).to receive(:new).and_raise(RuntimeError, "x" * 160)
    expect(cli("run").call).to eq(3)
    expect(err.string).to include("internal error (RuntimeError: #{'x' * 160})")
    expect(err.string).not_to include("...")
  end

  it "truncates a crash message one character past the cap" do
    allow(Saboteur::Engine).to receive(:new).and_raise(RuntimeError, "x" * 161)
    expect(cli("run").call).to eq(3)
    expect(err.string).to include("internal error (RuntimeError: #{'x' * 160}...)")
  end

  it "re-reads a byte-tagged crash message as UTF-8" do
    allow(Saboteur::Engine).to receive(:new).and_raise(RuntimeError, "caf\xC3\xA9\xFF".b)
    expect(cli("run").call).to eq(3)
    expect(err.string).to include("internal error (RuntimeError: caf\u00E9?)")
  end

  it "renders a crash whose message is not a String" do
    weird = stub_const("WeirdError", Class.new(StandardError) { def message = 42 })
    allow(Saboteur::Engine).to receive(:new).and_raise(weird)
    expect(cli("run").call).to eq(3)
    expect(err.string).to include("internal error (WeirdError: 42)")
  end

  it "writes the crash backtrace to .saboteur/internal-error.log and names the path" do
    allow(Saboteur::Engine).to receive(:new).and_raise(RuntimeError, "boom")
    Dir.mktmpdir do |root|
      Dir.chdir(root) do
        expect(cli("run").call).to eq(3)
        expect(err.string).to include("full backtrace: .saboteur/internal-error.log")
        expect(File.read(File.join(root, ".saboteur", "internal-error.log"))).to include("RuntimeError")
      end
    end
  end

  it "writes the crash log under the configured cache_dir" do
    allow(Saboteur::Engine).to receive(:new).and_raise(RuntimeError, "boom")
    Dir.mktmpdir do |root|
      File.write(File.join(root, "custom.rb"), "Saboteur.configure { |c| c.cache_dir = '.custom-cache' }\n")
      Dir.chdir(root) do
        expect(cli("run", "--config", "custom.rb").call).to eq(3)
        expect(err.string).to include("full backtrace: .custom-cache/internal-error.log")
        expect(File.read(File.join(root, ".custom-cache", "internal-error.log"))).to include("RuntimeError")
      end
    end
  end

  it "falls back to the bare one-liner when cache_dir is unset" do
    allow(Saboteur::Engine).to receive(:new).and_raise(RuntimeError, "boom")
    Dir.mktmpdir do |root|
      File.write(File.join(root, "custom.rb"), "Saboteur.configure { |c| c.cache_dir = nil }\n")
      Dir.chdir(root) do
        expect(cli("run", "--config", "custom.rb").call).to eq(3)
        expect(err.string).to include("internal error (RuntimeError: boom)")
        expect(err.string).not_to include("full backtrace")
      end
    end
  end

  it "does not build a log path when cache_dir is nil" do
    command = cli("run")
    allow(command).to receive(:config).and_return(instance_double(Saboteur::Config, path: nil))
    allow(File).to receive(:join).and_call_original
    expect(command.send(:crash_log_path)).to be_nil
    expect(File).not_to have_received(:join)
  end

  it "prints the crash backtrace to stderr with --verbose" do
    error = RuntimeError.new("boom")
    error.set_backtrace(["app/models/thing.rb:10:in `explode'"])
    allow(Saboteur::Engine).to receive(:new).and_raise(error)
    expect(cli("run", "--verbose").call).to eq(3)
    expect(err.string).to include("app/models/thing.rb:10:in `explode'")
  end

  it "keeps the crash backtrace off stderr without --verbose" do
    error = RuntimeError.new("boom")
    error.set_backtrace(["app/models/thing.rb:10:in `explode'"])
    allow(Saboteur::Engine).to receive(:new).and_raise(error)
    expect(cli("run").call).to eq(3)
    expect(err.string).not_to include("app/models/thing.rb:10")
  end

  it "reports an unexpected failure in agent mode as an agent failure and exits 3" do
    allow(Saboteur::Engine).to receive(:new).and_raise(RuntimeError, "boom")
    expect(cli("run", "--agent").call).to eq(3)
    expect(out.string).to include("internal error (RuntimeError: boom)")
  end

  it "parses run options into config overrides" do
    command = cli("run", "--since", "main", "--subject", "A#b", "--subject", "C.d",
                  "--timeout-factor", "2.5", "--jobs", "1", "--reeval", "nesting", "--no-cache", "--seed", "42")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to eq(since: "main", subjects: ["A#b", "C.d"], timeout_factor: 2.5, jobs: 1,
                                  reeval: "nesting", cache: false, seed: 42)
  end

  it "parses --baseline-passes into config overrides (#55)" do
    command = cli("run", "--baseline-passes", "1")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to eq(baseline_passes: 1)
  end

  it "parses --max-duration with a unit suffix into seconds, plus --max-duration-ok (#245)" do
    command = cli("run", "--max-duration", "10m", "--max-duration-ok")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to eq(max_duration: 600.0, max_duration_ok: true)
  end

  it "parses --max-duration suffixes s and h, and bare seconds (#245)" do
    { "30s" => 30.0, "2h" => 7200.0, "45" => 45.0 }.each do |text, seconds|
      command = cli("run", "--max-duration", text)
      allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
      command.call
      expect(command.options).to eq(max_duration: seconds)
    end
  end

  it "rejects an unparseable --max-duration as a usage error (#245)" do
    command = cli("run", "--max-duration", "soon")
    expect(command.call).to eq(2)
    expect(err.string).to include("invalid --max-duration")
  end

  it "expands the pr preset into its flag bundle, default ref main (#244)" do
    command = cli("pr")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(since: "main", baseline_passes: 1, max_duration: 600.0,
                                       max_duration_ok: true)
    expect(err.string).to include("preset 'pr':")
  end

  it "announces the pr preset expansion in full (#296)" do
    command = cli("pr")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(err.string).to include("saboteur: preset 'pr': --baseline-passes 1 --max-duration 10m " \
                                  "--max-duration-ok --since main (explicit flags override)")
  end

  it "takes the pr ref from the first operand even with trailing flags (#296)" do
    command = cli("pr", "v1.0", "--verbose")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(since: "v1.0")
  end

  it "takes the pr ref as the first operand and lets explicit flags override the bundle (#244)" do
    command = cli("pr", "origin/develop", "--baseline-passes", "2")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(since: "origin/develop", baseline_passes: 2, max_duration: 600.0)
  end

  it "expands the audit preset into a whole-project run with both reports (#244)" do
    command = cli("audit")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(all: true, json_report: ".saboteur/audit-report.json",
                                       html_report: ".saboteur/audit-report.html")
    expect(err.string).to include("preset 'audit':")
  end

  it "expands the audit preset with all operators and both baseline checks (#245)" do
    command = cli("audit")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(operators: ["all"], baseline_passes: 2)
  end

  it "lets an explicit --guess-tests replace the audit preset's injected --all too (#245)" do
    command = cli("audit", "--guess-tests")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options[:all]).to be_falsey
  end

  it "lets an explicit --test replace the audit preset's injected --all (#245)" do
    command = cli("audit", "--test", "spec/models/person_spec.rb")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(tests: ["spec/models/person_spec.rb"])
    expect(command.options[:all]).to be_falsey
  end

  it "never injects a --since ref for presets other than pr (#245)" do
    command = cli("audit")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).not_to have_key(:since)
  end

  it "defaults the pr ref to main when only flags follow (#245)" do
    command = cli("pr", "--baseline-passes", "2")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(since: "main", baseline_passes: 2)
  end

  it "keeps the audit preset's --all when no explicit scope flag is given (#245)" do
    command = cli("audit", "--seed", "7")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(all: true, seed: 7)
  end

  it "lets the --test=path form replace the audit preset's injected --all (#245)" do
    command = cli("audit", "--test=spec/models/person_spec.rb")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(tests: ["spec/models/person_spec.rb"])
    expect(command.options[:all]).to be_falsey
  end

  it "announces the expanded preset flags (#245)" do
    command = cli("pr")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(err.string).to include("preset 'pr':").and include("--since main")
  end

  it "rejects a whitespace-padded --max-duration with the value in the message (#245)" do
    command = cli("run", "--max-duration", " 10m ")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to eq(max_duration: 600.0)
    bad = cli("run", "--max-duration", "soon")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    bad.call
    expect(err.string).to include('"soon"')
  end

  it "keeps an explicit --no-max-duration-ok over a config true in the agent settings (#245)" do
    Dir.mktmpdir do |root|
      path = File.join(root, "saboteur.rb")
      File.write(path, "Saboteur.configure { |c| c.max_duration_ok = true }")
      command = cli("run", "--agent", "--no-max-duration-ok", "--config", path)
      allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
      command.call
      expect(command.options[:max_duration_ok]).to be(false)
      expect(command.send(:agent_settings)[:max_duration_ok]).to be(false)
    end
  end

  it "lets --no-max-duration-ok override the pr preset's budget pass (#245)" do
    command = cli("pr", "--no-max-duration-ok")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(max_duration: 600.0, max_duration_ok: false)
  end

  describe "doctor suite options" do
    before { allow(Saboteur::Doctor).to receive(:new).and_return(instance_double(Saboteur::Doctor, call: true)) }

    it "does not run the suite by default" do
      expect(cli("doctor").call).to eq(0)
      expect(Saboteur::Doctor).to have_received(:new).with(anything, out: out, suite: false)
    end

    it "runs the suite with --suite" do
      cli("doctor", "--suite").call
      expect(Saboteur::Doctor).to have_received(:new).with(anything, out: out, suite: true)
    end

    it "runs the suite on the given specs with --test, which the config sees" do
      command = cli("doctor", "--test", "spec/saboteur/cli_spec.rb")
      command.call
      expect(Saboteur::Doctor).to have_received(:new).with(anything, out: out, suite: true)
      expect(command.config["tests"]).to eq(["spec/saboteur/cli_spec.rb"])
    end

    it "keeps --suite out of the config overrides" do
      allow(Saboteur::Config).to receive(:load).and_return(Saboteur::Config.new)
      cli("doctor", "--suite").call
      expect(Saboteur::Config).to have_received(:load).with(root: Dir.pwd, path: nil, overrides: {})
    end

    it "collects every repeated --test spec" do
      command = cli("doctor", "--test", "spec/saboteur/cli_spec.rb", "--test", "spec/saboteur/help_spec.rb")
      command.call
      expect(command.config["tests"]).to eq(%w[spec/saboteur/cli_spec.rb spec/saboteur/help_spec.rb])
    end

    it "exits 2 when a --test spec does not exist" do
      expect(cli("doctor", "--test", "spec/nope_spec.rb").call).to eq(2)
      expect(err.string).to include("test file not found: spec/nope_spec.rb")
    end

    it "exits 3 with a plain diagnostic and writes nothing when the sandbox probe is refused" do
      failing = instance_double(Saboteur::Doctor)
      message = "sandbox is on but the Landlock probe failed (EPERM); a run would refuse the same way - " \
                "set c.sandbox = false to check without it"
      allow(failing).to receive(:call).and_raise(Saboteur::Error, message)
      allow(Saboteur::Doctor).to receive(:new).and_return(failing)
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { expect(cli("doctor").call).to eq(3) }
        expect(File).not_to exist(File.join(dir, ".saboteur"))
      end
      expect(err.string).to include("saboteur: sandbox is on but the Landlock probe failed (EPERM)")
    end
  end

  it "rejects contradictory test selection flags as usage errors, before any file check" do
    expect(cli("run", "--all", "--test", "spec/nope_spec.rb").call).to eq(2)
    expect(err.string).to include("--all cannot be combined with --test")
    expect(cli("run", "--all", "--guess-tests").call).to eq(2)
    expect(err.string).to include("--all cannot be combined with --guess-tests")
    expect(cli("run", "--guess-tests", "--test", "spec/nope_spec.rb").call).to eq(2)
    expect(err.string).to include("--guess-tests cannot be combined with --test")
  end

  it "warns that --no-guess-tests is deprecated and no longer restores the whole suite" do
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    cli("run", "--no-guess-tests").call
    expect(err.string).to include("guess_tests = false is deprecated: inferred specs are the default " \
                                  "and it no longer restores the whole suite")
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

    it "appends the run to the score history when --score-history is set" do
      history = File.join(File.realpath(Dir.mktmpdir), "history.jsonl")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:killed)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      json = File.join(File.realpath(Dir.mktmpdir), "r.json")
      expect(cli("run", "--score-history", history, "--json", json).call).to eq(0), "stderr: #{err.string}"
      expect(err.string).to include("saboteur: score history: first record")
      lines = File.readlines(history)
      expect(lines.size).to eq(1)
      expect(JSON.parse(lines[0])["operatorPolicy"]).to eq(Saboteur::Config.new({}).operator_policy)
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

    def killed(count)
      Array.new(count) { result_for(:killed) }
    end

    it "is 0 when timeouts and errors stay within --max-timeouts and --max-errors" do
      report = report_of(*killed(8), result_for(:timeout), result_for(:error))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
      expect(cli("run", "--max-timeouts", "1", "--max-errors", "10%", "--json",
                 File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
    end

    it "is 1 when errors are above --max-errors, with the error count named" do
      report = report_of(*killed(8), result_for(:error), result_for(:error))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
      json = File.join(Dir.mktmpdir, "r.json")
      expect(cli("run", "--max-errors", "1", "--json", json).call).to eq(1)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("maxErrors")
    end

    it "keeps survivors and the threshold as the stated cause when they fail too" do
      report = report_of(result_for(:killed), result_for(:survived), result_for(:timeout))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report,
                                                                                            guessed_tests: nil))
      json = File.join(Dir.mktmpdir, "r.json")
      expect(cli("run", "--max-timeouts", "0", "--json", json).call).to eq(1)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("survivors")
    end

    it "lets --max-errors, not --threshold, judge errored mutants" do
      report = report_of(*killed(8), result_for(:error))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
      expect(cli("run", "--threshold", "50", "--max-errors", "1", "--json",
                 File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
    end

    it "still makes an errored mutant incomplete under --threshold with only --max-timeouts" do
      report = report_of(*killed(8), result_for(:error))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
      expect(cli("run", "--threshold", "50", "--max-timeouts", "1", "--json",
                 File.join(Dir.mktmpdir, "r.json")).call).to eq(3)
    end

    it "refuses the count gates with --agent, like --threshold" do
      expect(cli("run", "--agent", "--max-errors", "1").call).to eq(2)
      expect(err.string).to include("--max-* gates cannot be combined with --agent")
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

    # A config-less directory: the repository's own dogfood config sets
    # c.test_selection = :all, which agent settings record.
    it "records only run-setting flags plus the resolved operator policy in agent settings" do
      report = report_of(result_for(:killed))
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow(Saboteur::Reporter::Agent).to receive(:call).and_call_original
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { cli("run", "--agent", "--jobs", "2").call }
      end
      expect(Saboteur::Reporter::Agent).to have_received(:call) do |_report, provenance|
        expect(provenance.settings).to eq(jobs: 2, operators: [], exclude_operators: [])
      end
    end

    it "omits --all from agent settings when named tests win over a configured whole-suite selection" do
      report = report_of(result_for(:killed))
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow(Saboteur::Reporter::Agent).to receive(:call).and_call_original
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("config")
          File.write("config/saboteur.rb", "Saboteur.configure { |c| c.test_selection = :all }\n")
          FileUtils.mkdir_p("spec")
          File.write("spec/a_spec.rb", "# spec\n")
          cli("run", "--agent", "--test", "spec/a_spec.rb").call
        end
      end
      expect(Saboteur::Reporter::Agent).to have_received(:call) do |_report, provenance|
        expect(provenance.settings).to eq(operators: [], exclude_operators: [])
        expect(provenance.tests).to eq(["spec/a_spec.rb"])
      end
    end

    it "prints the complete replay command for a survivor, carrying the run's own selection options (#261)" do
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:survived)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("config")
          File.write("config/saboteur.rb", "# config\n")
          FileUtils.mkdir_p("spec")
          File.write("spec/a_spec.rb", "# spec\n")
          FileUtils.mkdir_p("spec/space dir")
          File.write("spec/space dir/b_spec.rb", "# spec\n")
          system("git", "init", "-q", out: File::NULL, exception: true)
          system("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty",
                 "-m", "base", out: File::NULL, exception: true)
          cli("run", "--config", "config/saboteur.rb", "--since", "HEAD", "--subject", "Person#adult?", "--test",
              "spec/a_spec.rb", "--test", "spec/space dir/b_spec.rb", "--allow-hazardous").call
        end
      end
      line = out.string.lines.find { |l| l.include?("replay one survivor:") }
      require "shellwords"
      words = Shellwords.split(line.split(":", 2).last)
      expect(words).to include("saboteur", "run", "--id", "--config", "config/saboteur.rb", "--since", "HEAD",
                               "--subject", "Person#adult?", "--test", "spec/a_spec.rb")
      expect(words.each_cons(2).to_a).to include(["--test", "spec/space dir/b_spec.rb"])
      expect(words).to include("--allow-hazardous")
      expect(out.string).not_to include("add this run's own")
    end

    it "carries --allow-focus into the survivor replay command (#261)" do
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:survived)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("spec")
          File.write("spec/a_spec.rb", "# spec\n")
          system("git", "init", "-q", out: File::NULL, exception: true)
          system("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty",
                 "-m", "base", out: File::NULL, exception: true)
          cli("run", "--subject", "Person#adult?", "--test", "spec/a_spec.rb", "--allow-focus").call
        end
      end
      line = out.string.lines.find { |l| l.include?("replay one survivor:") }
      require "shellwords"
      expect(Shellwords.split(line.split(":", 2).last)).to include("--allow-focus")
    end

    it "prints the footer command in full when the selection runs past the agent byte cap (#261)" do
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:survived)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow(Saboteur::WorkingTree).to receive(:new).and_call_original
      tests = Array.new(40) { |i| "spec/padded selection #{i}/a_spec.rb" }
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("config")
          File.write("config/saboteur.rb", "# config\n")
          tests.each do |test|
            FileUtils.mkdir_p(File.dirname(test))
            File.write(test, "# spec\n")
          end
          system("git", "init", "-q", out: File::NULL, exception: true)
          system("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty",
                 "-m", "base", out: File::NULL, exception: true)
          cli("run", "--config", "config/saboteur.rb", "--since", "HEAD",
              *tests.flat_map { |test| ["--test", test] }).call
        end
      end
      line = out.string.lines.find { |l| l.include?("replay one survivor:") }
      expect(line.bytesize).to be > 1024
      expect(line).to include("spec/padded\\ selection\\ 39/a_spec.rb")
      expect(out.string).not_to include("add this run's own")
      expect(Saboteur::WorkingTree).to have_received(:new)
        .with(kind_of(String), ignored: kind_of(Array)).at_least(:once)
    end

    it "passes --verbose to the engine only for text runs (#262)" do
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:killed)))
      kwargs_seen = []
      allow(Saboteur::Engine).to receive(:new) { |*_args, **kwargs| kwargs_seen << kwargs and engine }
      cli("run", "--verbose").call
      cli("run", "--agent", "--verbose").call
      expect(kwargs_seen[0][:verbose]).to be(true)
      expect(kwargs_seen[1]).not_to have_key(:verbose)
    end

    it "records config-defined tests in agent provenance so the rerun keeps them" do
      report = report_of(result_for(:killed))
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow(Saboteur::Reporter::Agent).to receive(:call).and_call_original
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("config")
          File.write("config/saboteur.rb", "Saboteur.configure { |c| c.tests = [\"spec/a_spec.rb\"] }\n")
          FileUtils.mkdir_p("spec")
          File.write("spec/a_spec.rb", "# spec\n")
          cli("run", "--agent").call
        end
      end
      expect(Saboteur::Reporter::Agent).to have_received(:call) do |_report, provenance|
        expect(provenance.tests).to eq(["spec/a_spec.rb"])
        expect(Saboteur::Reporter::Agent::Commands.rerun(provenance)).to include("--test spec/a_spec.rb")
      end
    end

    it "records a configured test_selection = :all in agent settings when no tests resolved" do
      report = report_of(result_for(:killed))
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow(Saboteur::Reporter::Agent).to receive(:call).and_call_original
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("config")
          File.write("config/saboteur.rb", "Saboteur.configure { |c| c.test_selection = :all }\n")
          cli("run", "--agent").call
        end
      end
      expect(Saboteur::Reporter::Agent).to have_received(:call) do |_report, provenance|
        expect(provenance.settings).to eq(all: true, operators: [], exclude_operators: [])
      end
    end

    it "records --all in agent settings so rerun and replay keep the whole-suite scope" do
      report = report_of(result_for(:killed))
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow(Saboteur::Reporter::Agent).to receive(:call).and_call_original
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { cli("run", "--agent", "--all", "--jobs", "2").call }
      end
      expect(Saboteur::Reporter::Agent).to have_received(:call) do |_report, provenance|
        expect(provenance.settings).to eq(jobs: 2, all: true, operators: [], exclude_operators: [])
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

    it "writes maxTimeouts into the JSON report when too many mutants time out" do
      json = File.join(Dir.mktmpdir, "r.json")
      report = report_of(result_for(:killed), result_for(:killed), result_for(:timeout))
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
      expect(cli("run", "--max-timeouts", "0", "--json", json).call).to eq(1)
      expect(JSON.parse(File.read(json)).dig("saboteur", "exitCause")).to eq("maxTimeouts")
      expect(err.string).to include("1 timeout mutants, above --max-timeouts 0")
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

  it "describes --exclude-operators in run help" do
    Saboteur::CLI.new(%w[run --help], out: out, err: StringIO.new).call
    expect(out.string).to include("--exclude-operators NAMES", "Exclude operator names from the selected set")
  end

  it "marks only the named operators on in --list-operators" do
    expect(cli("run", "--list-operators", "--operators", "range").call).to eq(0)
    expect(out.string).to match(/^range\s+on/)
    expect(out.string).to match(/^arithmetic\s+off/)
  end

  it "parses --matrix into the matrix config key, and describes it in help" do
    command = cli("run", "--matrix")
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options).to include(matrix: true)
    expect(Saboteur::Config.new(command.options.transform_keys(&:to_s))["matrix"]).to be(true)
    out = StringIO.new
    Saboteur::CLI.new(%w[run --help], out: out, err: StringIO.new).call
    expect(out.string).to include("--matrix", "Run every covering test per mutant and list blind and redundant tests")
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
      expect(out.string).to include("saboteur #{Saboteur::VERSION}:", "Reports: #{path} (JSON)")
      expect(File).to exist(path)
    end
  end

  it "writes the HTML report it names, next to the JSON one" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "r.html")
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine,
                                                                          call: report_of(result_for(:killed))))
      cli("run", "--json", File.join(dir, "r.json"), "--html", path).call
      expect(out.string).to include("Reports: #{File.join(dir, 'r.json')} (JSON), #{path} (HTML)")
      expect(out.string.scan("Reports:").size).to eq(1)
      expect(File.read(path)).to start_with("<!DOCTYPE html>")
    end
  end

  it "names both reports on one Reports line with paths relative to the root" do
    Dir.mktmpdir do |dir|
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine,
                                                                          call: report_of(result_for(:killed))))
      Dir.chdir(dir) { cli("run").call }
      expect(out.string).to include("\nReports: .saboteur/report.json (JSON), .saboteur/report.html (HTML)\n")
      expect(out.string).not_to include("JSON report:")
    end
  end

  it "prints no Reports line and writes nothing when both reports are null" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "saboteur.rb"),
                 "Saboteur.configure { |c| c.html_report = nil; c.json_report = nil }\n")
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine,
                                                                          call: report_of(result_for(:killed))))
      Dir.chdir(dir) { cli("run").call }
      expect(out.string).not_to include("Reports:")
      expect(Dir.glob("#{dir}/.saboteur/report.*")).to be_empty
    end
  end

  it "writes no HTML report when html_report is null in the config" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "saboteur.rb"), "Saboteur.configure { |c| c.html_report = nil }\n")
      allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine,
                                                                          call: report_of(result_for(:killed))))
      Dir.chdir(dir) { cli("run").call }
      expect(out.string).to include("Reports: .saboteur/report.json (JSON)\n")
      expect(out.string).not_to include("HTML")
      expect(Dir.glob("#{dir}/**/*.html")).to be_empty
    end
  end

  describe "--since with a ref that is not a commit" do
    it "exits 2 with a usage message, in text and in agent mode" do
      Dir.mktmpdir do |dir|
        Open3.capture3("git", "init", "-q", chdir: dir)
        allow(Saboteur::Engine).to receive(:new)

        Dir.chdir(dir) do
          expect(cli("run", "--since", "no-such-ref").call).to eq(2)
          expect(err.string).to include("saboteur: --since no-such-ref: not a commit in this repository")
          expect(cli("run", "--agent", "--since", "no-such-ref").call).to eq(2)
        end
        expect(Saboteur::Engine).not_to have_received(:new)
      end
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

    it "describes --suite and --test in doctor's help" do
      expect(cli("doctor", "--help").call).to eq(0)
      expect(out.string).to include("--suite", "Also run the unchanged suite twice (slow on a large suite)",
                                    "--test PATH", "Implies --suite")
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

  # Since 0.7.0 the configured include names the sources, so --test may
  # stand alone; agent follow-up commands rely on that.
  it "accepts --test without a source, scoped by the configured include" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "# spec\n")
        command = cli("run", "--test", "spec/a_spec.rb")
        allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
        expect(command.call).to eq(3)
        expect(command.options[:tests]).to eq(%w[spec/a_spec.rb])
        expect(err.string).not_to include("--test needs")
        expect(err.string).not_to include("test file not found")
      end
    end
  end

  # A pull-request run: --since already names the sources (the changed
  # files), so listing them again only repeats the diff.
  it "accepts --test without a source when --since scopes the run" do
    command = cli("run", "--since", "origin/main", "--test", "spec/a_spec.rb")
    # Past the argument checks, the run stops on the ref: this directory is no git repository.
    expect(command.call).to eq(2)
    expect(err.string).to include("--since needs a git repository")
    expect(err.string).not_to include("--test needs")
    expect(command.options[:tests]).to eq(%w[spec/a_spec.rb])
    expect(command.options[:include]).to be_nil
  end

  it "accepts --test without a source when since comes from the config file" do
    FileUtils.mkdir_p("config")
    File.write("config/saboteur.rb", "Saboteur.configure { |c| c.since = \"origin/main\" }\n")
    command = cli("run", "--test", "spec/a_spec.rb")
    expect(command.call).to eq(2)
    expect(err.string).to include("--since needs a git repository")
    expect(err.string).not_to include("--test needs")
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
