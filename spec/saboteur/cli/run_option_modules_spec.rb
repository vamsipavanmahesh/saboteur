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
      "--[no-]color" => "Colour the text report (default: on for a terminal unless NO_COLOR is set)"
    }.each do |flag, help|
      expect(text).to match(/#{Regexp.escape(flag)}\s+#{Regexp.escape(help)}/), "no help text after #{flag}"
    end
  end

  it "keeps the run --help flag order stable across the extraction" do
    out = StringIO.new
    Saboteur::CLI.new(["run", "--help"], out:, err: StringIO.new).call
    text = out.string
    # --fail-fast sits between --allow-hazardous and --incremental, after the
    # run-budget group (--jobs, --max-duration); execution before matrix.
    order = ["--jobs", "--max-duration ", "--allow-hazardous", "--fail-fast", "--incremental", "--test-command",
             "--matrix"]
    positions = order.map { |flag| text.index(flag) }
    expect(positions).to all(be_a(Integer))
    expect(positions).to eq(positions.sort)
  end
end
