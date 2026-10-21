# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "json"
require "tmpdir"
require_relative "../support/report_helpers"

RSpec.describe Saboteur::CLI, "terminal options" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:reporter) { instance_double(Saboteur::Reporter::Terminal, call: nil) }

  before do
    engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:killed)))
    allow(Saboteur::Engine).to receive(:new).and_return(engine)
    allow(Saboteur::Reporter::Terminal).to receive(:new) { |*_a, **_kw| reporter }
  end

  def run_with(*flags)
    described_class.new(["run", *flags], out: out, err: err).call
  end

  def expect_reporter(**kwargs)
    defaults = { verbose: false, quiet: false, color: :auto, overrides: {}, replay_command: kind_of(Proc),
                 all_mutants: false, details: false, exit_code: 0, threshold: nil, previous_score: nil,
                 baseline_gate: nil }
    expect(Saboteur::Reporter::Terminal).to have_received(:new).with(out, **defaults, **kwargs)
  end

  it "defaults to a quiet reporter with automatic colour" do
    run_with
    expect_reporter
  end

  it "passes --verbose to the reporter" do
    run_with("--verbose")
    expect_reporter(verbose: true)
  end

  it "passes --color and --no-color to the reporter" do
    run_with("--color")
    expect_reporter(color: :always)
    run_with("--no-color")
    expect_reporter(color: :never)
  end

  it "passes --quiet to the reporter" do
    run_with("--quiet")
    expect_reporter(quiet: true)
  end

  it "passes --all-mutants to the reporter, defaulting to collapsed findings" do
    run_with("--all-mutants")
    expect_reporter(all_mutants: true)
  end

  it "passes --details to the reporter, defaulting to the short first screen" do
    run_with("--details")
    expect_reporter(details: true)
  end

  describe "--fail-fast" do
    let(:stop) { Saboteur::EarlyStop.new(reason: "fail_fast", unreached: %w[A#x], truncated: [], unverified: []) }

    def stopped_report(*results)
      Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1.0,
                           root: File.dirname(person_subject.file), seed: 1, early_stop: stop)
    end

    def run_recording(report, *flags)
      allow(Saboteur::Engine).to receive(:new).and_return(
        instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
      )
      Dir.mktmpdir do |dir|
        json = File.join(dir, "r.json")
        code = described_class.new(["run", *flags, "--json", json], out: out, err: err).call
        [code, JSON.parse(File.read(json))]
      end
    end

    it "turns the option into the fail_fast setting" do
      run_with("--fail-fast", "--jobs", "1")
      expect(Saboteur::Engine).to have_received(:new).with(satisfy { |config| config["fail_fast"] == true }, any_args)
    end

    it "fails a stopped run even when every mutant that ran was killed, and records why" do
      code, json = run_recording(stopped_report(result_for(:killed)))
      expect([code, json.dig("saboteur", "exitCause")]).to eq([1, "failFast"])
    end

    it "fails a stopped run whatever the threshold says" do
      code, json = run_recording(stopped_report(result_for(:killed)), "--threshold", "10")
      expect([code, json.dig("saboteur", "exitCause")]).to eq([1, "failFast"])
    end

    it "still passes the same run when it was not stopped" do
      complete = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                      root: File.dirname(person_subject.file), seed: 1)
      code, json = run_recording(complete)
      expect([code, json.dig("saboteur", "exitCause")]).to eq([0, "ok"])
    end

    it "records failFast as the cause in agent mode for a stopped run, and survivors otherwise" do
      _code, stopped = run_recording(stopped_report(result_for(:survived)), "--agent")
      _code, plain = run_recording(report_of(result_for(:survived)), "--agent")
      expect([stopped.dig("saboteur", "exitCause"), plain.dig("saboteur", "exitCause")]).to eq(%w[failFast survivors])
    end
  end

  describe "help" do
    it "describes --fail-fast, --verbose and --color" do
      text = begin
        described_class.new(%w[run --help], out: out, err: err).call
        out.string
      end
      expect(text).to include("--fail-fast", "Stop after the first subject with a survivor (needs --jobs 1)",
                              "--verbose", "Text report: also print score split, timings and kill causes;",
                              "a crash prints its backtrace", "--color [MODE]",
                              "Colour the text report: always, never or auto (default: auto)",
                              "--no-color", "Deprecated alias for --color=never")
    end
  end
end
