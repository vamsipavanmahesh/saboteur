# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "run option modules (#334)" do
  {
    Saboteur::CLI::ExecutionOptions => :define_execution_options,
    Saboteur::CLI::MatrixOption => :define_matrix_option,
    Saboteur::CLI::OutputOptions => :define_output_options,
    Saboteur::CLI::ExplicitFileOptions => :define_explicit_file_options
  }.each do |mod, define_method|
    it "mixes #{mod} into Saboteur::CLI like the other option modules" do
      expect(Saboteur::CLI.ancestors).to include(mod)
    end

    it "#{mod} owns #{define_method}, moved out of CLI itself" do
      expect(mod.private_instance_methods(false)).to include(define_method)
      expect(Saboteur::CLI.private_instance_methods(false)).not_to include(define_method)
    end
  end
  # Every moved opts.on line keeps its help text attached to its flag: a
  # swapped or emptied string must not survive the dogfood (#754 pattern).
  it "keeps every extracted option's help text attached to its flag" do
    out = StringIO.new
    Saboteur::CLI.new(["run", "--help"], out:, err: StringIO.new).call
    text = out.string
    {
      "--timeout-factor N" => "Multiple of baseline runtime (default 3)",
      "--jobs N" => "Concurrent workers (default 1)",
      "--config PATH" => "Config file (default config/saboteur.rb)",
      "--integration NAME" => "Test adapter (rspec)",
      "--reeval STRATEGY" => "class_eval or nesting",
      "--no-cache" => "Rebuild the coverage map",
      "--allow-hazardous" => "Also run mutants inside destructive calls (rm_rf, system, ...)",
      "--fail-fast" => "Stop after the first subject with a survivor (needs --jobs 1)",
      "--incremental" => "Reuse earlier verdicts whose inputs did not change",
      "--resume DIR" => "Keep verdicts in DIR and reuse them in a later run with the same inputs",
      "--allow-focus" => "Run even when a focus filter (fit, fdescribe, :focus) narrows the suite",
      "--all" => "Run the whole configured test suite instead of inferring the specs named after the mutated files",
      "--test-command CMD" => "Run CMD per mutant in the project root",
      "--[no-]guess-tests" => "Deprecated alias: inferred specs are already the default",
      "--test PATH" => "Spec file or directory to run; repeatable. Replaces the configured spec paths",
      "--threshold PERCENT" => "Exit 1 when the score is below PERCENT (0-100)",
      "--matrix" => "Run every covering test per mutant and list blind and redundant tests",
      "--score-history PATH" => "Append score history JSONL (opt-in)",
      "--json PATH" => "Stryker JSON report path",
      "--html PATH" => "Self-contained HTML report path",
      "--format FORMAT" => "text, agent or json (--dry-run inventory)",
      "--agent" => "Same as --format agent",
      "--verbose" => "Text report: also print score split, timings and kill causes",
      "--color [MODE]" => "Colour the text report: always, never or auto (default: auto)",
      "--no-color" => "Deprecated alias for --color=never",
      "--all-mutants" => "Text report: list every survived mutant;",
      "--with-timeouts" => "Text report: render each timeout as a full finding block;",
      "--quiet" => "Text report: print only the findings and the verdict"
    }.each do |flag, help|
      expect(text).to match(/#{Regexp.escape(flag)}\s+#{Regexp.escape(help)}/), "no help text after #{flag}"
    end

    expect(text).to include("default: one finding per statement, with the label mix")
    expect(text).to include("default: one tally line per timeout")
    expect(text).to include("no effect with --format json/agent; ignores --all-mutants")
  end

  it "keeps the run --help flag order stable across the extraction" do
    out = StringIO.new
    Saboteur::CLI.new(["run", "--help"], out:, err: StringIO.new).call
    text = out.string
    # --fail-fast sits between --allow-hazardous and --incremental, after the
    # run-budget group (--jobs, --max-duration); execution before matrix.
    order = ["--jobs", "--max-duration ", "--allow-hazardous", "--fail-fast", "--incremental", "--resume",
             "--test-command", "--matrix"]
    positions = order.map { |flag| text.index(flag) }
    expect(positions).to all(be_a(Integer))
    expect(positions).to eq(positions.sort)
  end
end

# Parsing pins: every extracted flag keeps its name, declared arity and exact
# effect on the options hash, so argument_removal/argument_swap mutants inside
# the opts.on blocks cannot survive (#334, #754 pattern).
RSpec.describe "run option modules parsing (#334)" do
  def parse_run(*argv)
    cli = Saboteur::CLI.new(["run"])
    cli.parser.parse!(argv)
    cli
  end

  it "sets no run options by default" do
    expect(parse_run.options).to eq({})
  end

  it "parses the execution flags with their declared arity" do
    cli = parse_run("--timeout-factor", "2.5", "--jobs", "4", "--config", "cfg.yml",
                    "--integration", "rspec", "--reeval", "nesting")
    expect(cli.options).to eq(timeout_factor: 2.5, jobs: 4, config: "cfg.yml",
                              integration: "rspec", reeval: "nesting")
  end

  it "parses the toggle flags to their exact booleans" do
    cli = parse_run("--no-cache", "--allow-hazardous", "--fail-fast", "--incremental",
                    "--allow-focus", "--all")
    expect(cli.options).to eq(cache: false, allow_hazardous: true, fail_fast: true,
                              incremental: true, allow_focus: true, all: true)
  end

  it "parses --resume with its directory" do
    expect(parse_run("--resume", "state/run1").options).to eq(resume: "state/run1")
  end

  it "parses --test-command and --[no-]guess-tests" do
    expect(parse_run("--test-command", "bin/test").options).to eq(test_command: "bin/test")
    expect(parse_run("--guess-tests").options).to eq(guess_tests: true)
    expect(parse_run("--no-guess-tests").options).to eq(guess_tests: false)
  end

  it "collects repeated --test paths and parses --threshold as a Float" do
    expect(parse_run("--test", "a_spec.rb", "--test", "b_spec.rb").options)
      .to eq(tests: ["a_spec.rb", "b_spec.rb"])
    expect(parse_run("--threshold", "75.5").options).to eq(threshold: 75.5)
  end

  it "keeps the score-gate flags wired through Gates.define_options" do
    expect(parse_run("--max-timeouts", "3").options).to eq(max_timeouts: "3")
    expect(parse_run("--max-errors", "5%").options).to eq(max_errors: "5%")
  end

  it "accepts exactly the two --reeval strategies" do
    %w[class_eval nesting].each do |strategy|
      expect(parse_run("--reeval", strategy).options).to eq(reeval: strategy)
    end
    expect { parse_run("--reeval", "bogus") }.to raise_error(OptionParser::ParseError)
  end

  it "parses --matrix" do
    expect(parse_run("--matrix").options).to eq(matrix: true)
  end

  it "parses the report destination flags" do
    cli = parse_run("--score-history", "h.jsonl", "--json", "r.json", "--html", "r.html")
    expect(cli.options).to eq(score_history: "h.jsonl", json_report: "r.json", html_report: "r.html")
  end

  it "accepts exactly the three --format values" do
    %w[text agent json].each do |fmt|
      expect(parse_run("--format", fmt).instance_variable_get(:@format)).to eq(fmt)
    end
    expect { parse_run("--format", "yaml") }.to raise_error(OptionParser::ParseError)
  end

  it "parses --agent as --format agent" do
    expect(parse_run("--agent").instance_variable_get(:@format)).to eq("agent")
  end

  it "parses --verbose into both the ivar and the option" do
    cli = parse_run("--verbose")
    expect(cli.instance_variable_get(:@verbose)).to be(true)
    expect(cli.options).to eq(verbose: true)
  end

  it "parses --quiet into both the ivar and the option" do
    cli = parse_run("--quiet")
    expect(cli.instance_variable_get(:@quiet)).to be(true)
    expect(cli.options).to eq(quiet: true)
  end

  it "parses --color modes and keeps --color/--no-color as deprecated aliases" do
    expect(parse_run("--color").instance_variable_get(:@color)).to eq(:always)
    expect(parse_run("--no-color").instance_variable_get(:@color)).to eq(:never)
    expect(parse_run("--color=never").instance_variable_get(:@color)).to eq(:never)
    expect(parse_run("--color", "auto").instance_variable_get(:@color)).to eq(:auto)
    expect(parse_run("--color=always").instance_variable_get(:@color)).to eq(:always)
  end

  it "keeps the --verbose crash-backtrace help line" do
    out = StringIO.new
    Saboteur::CLI.new(["run", "--help"], out:, err: StringIO.new).call
    expect(out.string).to include("a crash prints its backtrace")
  end
end
