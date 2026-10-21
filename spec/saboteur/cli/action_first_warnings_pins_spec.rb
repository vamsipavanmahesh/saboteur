# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "shellwords"
require "stringio"

# PR4b pins: every warning class states what is wrong, then a "Fix:" line
# naming the real flag, config or edit that resolves it; crashes speak in
# the error:/help: voice - lowercase, no trailing period, one error per
# cause. The replay argv echo carries the budget the way the CLI accepted
# it, never a ".0"-mangled float.
RSpec.describe "action-first warnings and error voice (PR4b)" do
  it "dirty tree warning ends with the Fix line" do
    expect(Saboteur::DirtyTreeWarning::ADVICE).to eq(
      "Fix: commit or stash your changes first, or run on a CI checkout - " \
      "mutants run your code and could alter or delete files."
    )
  end

  it "unscoped suite warning carries a Fix line, and the --test it names parses" do
    cli = Saboteur::CLI.new(["run"])
    cli.parser.parse!(["--test", "spec/a_spec.rb"])
    expect(cli.options).to include(tests: ["spec/a_spec.rb"])

    diagnostics = instance_double(Saboteur::Engine::Diagnostics, warn: nil, inform: nil)
    integration = instance_double(Saboteur::Integration::RSpec,
                                  all_tests: Array.new(1000), test_files: %w[a_spec.rb b_spec.rb])
    Saboteur::Engine::UnscopedSuiteWarning.call(config: { "tests" => [], "all" => true, "baseline_passes" => 1 },
                                                diagnostics:, integration:, full_passes: 2)
    expect(diagnostics).to have_received(:warn) do |message|
      expect(message).to include("running the loaded suite unscoped: 1000 examples in 2 spec files")
      expect(message).to include("\n  Fix: pass --test to run only the specs you name")
    end
  end

  it "sandbox degraded notes name c.sandbox as the way out, and c.sandbox is a real config key" do
    expect(Saboteur::Config.new({ "sandbox" => false }, root: Dir.pwd)["sandbox"]).to eq(false)

    diagnostics = instance_double(Saboteur::Engine::Diagnostics)
    policy = Saboteur::Engine::SandboxPolicy.new(config: Saboteur::Config.new({}, root: Dir.pwd),
                                                 root: Dir.pwd, diagnostics:)
    allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(false)
    note = policy.send(:degraded_note, 2)
    expect(note).to include("children run with the hazard guard and canary only")
    expect(note).to include("\n  Fix: ")
    expect(note).to include("c.sandbox = false")
  end

  it "coverage warnings carry a Fix line" do
    store = Saboteur::Engine::CoverageStore.allocate
    expect(store.send(:preloaded_message, ["a.rb"]))
      .to include("\n  Fix: let the test suite load these files; a gemspec should require only its version file.")
  end

  it "crash report speaks error:/help:, lowercase, no trailing period" do
    err = StringIO.new
    code = Saboteur::CrashReport.call(RuntimeError.new("boom"), verbose: false, agent: false,
                                                                err:, out: StringIO.new, color: :never)
    expect(code).to eq(70)
    lines = err.string.lines.map(&:chomp)
    expect(lines.first).to eq("error: the run crashed (RuntimeError: boom)")
    expect(lines[1]).to start_with("help: ")
    expect(lines[1]).to include("please report it: https://github.com/vamsipavanmahesh/saboteur/issues")
    expect(lines[1]).not_to end_with(".")
  end

  it "crash agent JSON is byte-identical to the pre-voice shape" do
    out = StringIO.new
    Saboteur::CrashReport.call(RuntimeError.new("boom"), verbose: false, agent: true,
                                                         err: StringIO.new, out:, color: :never)
    expect(out.string).to include('"message": "internal error (RuntimeError: boom)"')
  end

  it "replay command echoes an integral float budget the way the CLI accepted it" do
    provenance = Saboteur::Reporter::Agent::Provenance.new(
      ref: "origin/main", seed: 7, head: "abc1234", working_tree: "clean", changed_files: 0, mode: "diff",
      json_report: ".saboteur/report.json", subjects: [], tests: [], sources: [], config_path: nil,
      digest: nil, cache: true, incremental: false,
      settings: { max_duration: 600.0 }
    )
    command = Saboteur::Reporter::Agent::Commands.replay(provenance, "abc", capped: false)
    expect(Shellwords.split(command).each_cons(2).to_a).to include(["--max-duration", "600"])
    expect(command).not_to include("600.0")
  end
end
