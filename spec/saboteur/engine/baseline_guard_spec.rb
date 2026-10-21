# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::BaselineGuard do
  around do |example|
    Dir.mktmpdir { |root| @root = root and example.run }
  end

  let(:config) { Saboteur::Config.new({ "seed" => 42 }, root: @root) }
  let(:integration) { double("adapter", test_files: [], all_tests: [Saboteur::Integration::TestCase.new(id: "t1", file: "spec/a.rb")]) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }
  let(:guard) do
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new))
  end

  def response(passed: true, executed: ["t1"], failed: [], error: nil, stopped: nil, payload: nil)
    contents = payload || JSON.generate(passed: passed, executed: executed, failed: failed, error: error)
    Saboteur::Execution::Supervisor::Result.new(payload: contents, exit_status: nil, stopped_by: stopped,
                                                detail: "deadline", runtime: 0.1, leftover_pids: [])
  end

  it "runs child setup hooks and seeds random values while recording a full result" do
    hooks = Saboteur::Hooks.new
    expect(hooks).to receive(:run).with(:after_fork)
    result = Saboteur::Integration::RunResult.new(passed: true, failed_ids: [], executed_ids: ["t1"], runtime: 0.1)
    expect(integration).to receive(:run_baseline).with(seed: 42).and_return(result)
    recorded = described_class.new(config: config, integration: integration, hooks: hooks,
                                   supervisor: supervisor, diagnostics: nil)
    writer = StringIO.new
    expect(FileUtils).to receive(:mkdir_p).with(File.join(@root, ".saboteur")).and_call_original
    expect($stdout).to receive(:reopen).with(File.join(@root, ".saboteur/baseline-1.log"), "w")
    expect($stdout).to receive(:sync=).with(true)
    expect($stderr).to receive(:reopen).with($stdout)
    recorded.send(:record, writer, 1)
    expect(JSON.parse(writer.string)["executed"]).to eq(["t1"])
    expect(rand).to eq(Random.new(42).rand)
  end

  it "retains hook/diagnostic collaborators and prepares before each supervised child" do
    diagnostics = instance_double(Saboteur::Engine::Diagnostics)
    allow(diagnostics).to receive(:inform)
    allow(diagnostics).to receive(:detail)
    heartbeat = instance_double(Saboteur::Engine::Diagnostics::ProgressHeartbeat, tick: nil)
    allow(heartbeat).to receive(:watch).and_return(heartbeat)
    allow(diagnostics).to receive(:progress_heartbeat).and_return(heartbeat)
    expect(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap).twice
    allow(supervisor).to receive(:run).and_return(response)
    checked = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                  supervisor: supervisor, diagnostics: diagnostics)
    checked.call
    expect(checked.send(:log_path, 1)).to eq(File.join(@root, ".saboteur/baseline-1.log"))
    expect(heartbeat).to have_received(:watch).with(File.join(@root, ".saboteur/baseline-1.log"))
    expect(heartbeat).to have_received(:watch).with(File.join(@root, ".saboteur/baseline-2.log"))
    expect(diagnostics).to have_received(:detail).with("checking the unchanged suite twice (seed 42)")
  end

  it "runs a single check and notes the tradeoff when baseline_passes is 1 (#55)" do
    single = Saboteur::Config.new({ "seed" => 42, "baseline_passes" => 1 }, root: @root)
    err = StringIO.new
    allow(supervisor).to receive(:run).and_return(response)
    diagnostics = Saboteur::Engine::Diagnostics.new(err, verbose: true)
    described_class.new(config: single, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: diagnostics).call
    expect(supervisor).to have_received(:run).once
    expect(err.string).to include("checking the unchanged suite once (seed 42)")
    expect(err.string).to include("order stability between passes is not checked (baseline_passes: 1)")
  end

  it "names c.max_processes when the process limit stops a healthy suite (#459)" do
    allow(supervisor).to receive(:run).and_return(response(stopped: :processes))
    expect do
      guard.call
    end.to raise_error(Saboteur::Error, /the suite stopped: processes.*c\.max_processes \(currently 64\)/)
  end

  it "names c.max_memory_mb when the memory limit stops a healthy suite (#459)" do
    allow(supervisor).to receive(:run).and_return(response(stopped: :memory))
    expect do
      guard.call
    end.to raise_error(Saboteur::Error, /the suite stopped: memory.*c\.max_memory_mb \(currently \d+ MB\)/)
  end

  it "pins the exact fork-limit stopped_reason string, hint and parens included (#459)" do
    allow(supervisor).to receive(:run).and_return(response(stopped: :processes))
    message = ["the suite stopped: processes (deadline). ",
               "If this suite forks heavily by design, raise the limit with c.max_processes (currently 64)"].join
    expect do
      guard.call
    end.to raise_error(Saboteur::Error, Regexp.new(Regexp.escape(message)))
  end

  it "pins the exact memory-limit stopped_reason string, hint and parens included (#459)" do
    allow(supervisor).to receive(:run).and_return(response(stopped: :memory))
    message = ["the suite stopped: memory (deadline). ",
               "If this suite legitimately needs more memory, ",
               "raise the limit with c.max_memory_mb (currently 2048 MB)"].join
    expect do
      guard.call
    end.to raise_error(Saboteur::Error, Regexp.new(Regexp.escape(message)))
  end

  it "estimates the remaining full passes once the first baseline pass is timed (#260)" do
    err = StringIO.new
    times = [100.0, 105.0]
    allow(Process).to receive(:clock_gettime) do |clock_id|
      raise "clock_gettime lost its clock id" unless clock_id == Process::CLOCK_MONOTONIC

      times.shift || 105.0
    end
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err, verbose: true),
                        full_passes: 3).call
    expect(err.string.scan(/baseline check \d+ took/).size).to eq(1)
    expect(err.string).to include("baseline check 1 took 5 s; about 10 s left for the remaining 1 full pass " \
                                  "and the coverage map build")
  end

  [true, false].each do |coverage_pending|
    it "prices two remaining baseline passes with coverage_pending=#{coverage_pending} (#499)" do
      triple = Saboteur::Config.new({ "seed" => 42, "baseline_passes" => 3 }, root: @root)
      err = StringIO.new
      allow(Process).to receive(:clock_gettime).and_return(100.0, 105.0)
      allow(supervisor).to receive(:run).and_return(response)
      described_class.new(config: triple, integration: integration, hooks: Saboteur::Hooks.new,
                          supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err, verbose: true),
                          full_passes: coverage_pending ? 4 : 3).call
      work = "the remaining 2 full passes"
      work += " and the coverage map build" if coverage_pending
      seconds = coverage_pending ? 15 : 10
      expect(err.string).to include("baseline check 1 took 5 s; about #{seconds} s left for #{work} at that rate")
      expect(err.string.scan(/baseline check \d+ took/).size).to eq(1)
      expect(err.string).not_to include("coverage map build") unless coverage_pending
    end
  end

  # The first timed pass prices the whole run against --max-duration:
  # warn while a Ctrl-C is still cheap (#637).
  # Warnings buffer into diagnostics.warnings; inform notes print (#640 area).
  def guard_with_budget(budget, full_passes: 3, baseline_passes: 2, run_started: 100.0)
    timed = Saboteur::Config.new({ "seed" => 42, "max_duration" => budget,
                                   "baseline_passes" => baseline_passes }, root: @root)
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    allow(Process).to receive(:clock_gettime).and_return(100.0, 105.0)
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: timed, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: diagnostics,
                        full_passes: full_passes, run_started: run_started).call
    diagnostics.warnings
  end

  it "warns when the projected baseline+coverage barely fits --max-duration (#637)" do
    expect(guard_with_budget(16.0).join).to include("projected baseline+coverage ~15s barely fits " \
                                                    "--max-duration 16s; mutants would get ~1s")
  end

  it "says the projection exceeds the budget when nothing is left for mutants (#637)" do
    expect(guard_with_budget(14.0).join).to include("projected baseline+coverage ~15s exceeds " \
                                                    "--max-duration 14s; mutants would get ~0s")
  end

  it "stays quiet when the budget comfortably fits the projection (#637)" do
    expect(guard_with_budget(25.0)).to be_empty
  end

  it "stays quiet when the budget leaves exactly one more pass after the projection (#637)" do
    expect(guard_with_budget(20.0)).to be_empty
  end

  it "says the projection exceeds the budget when exactly nothing is left for mutants (#637)" do
    expect(guard_with_budget(15.0).join).to include("projected baseline+coverage ~15s exceeds " \
                                                    "--max-duration 15s; mutants would get ~0s")
  end

  it "prices the mutants' share to one decimal (#637)" do
    expect(guard_with_budget(15.37).join).to include("mutants would get ~0.4s")
  end

  it "stays quiet when the run never started the clock, budget set or not (#637)" do
    expect(guard_with_budget(16.0, run_started: nil)).to be_empty
  end

  it "warns a hair under the one-more-pass boundary (#637)" do
    expect(guard_with_budget(19.99).join).to include("projected baseline+coverage ~15s barely fits --max-duration 20s")
  end

  it "says barely fits when only a hair is left for mutants (#637)" do
    expect(guard_with_budget(15.01).join).to include("projected baseline+coverage ~15s barely fits " \
                                                     "--max-duration 15s; mutants would get ~0s")
  end

  it "prints the full warning verbatim, share and remedies included (#637)" do
    expected = "raise --max-duration, pass fewer --baseline-passes, or narrow the scope\n  " \
               "projected baseline+coverage ~15s barely fits --max-duration 16s; " \
               "mutants would get ~1s"
    expect(guard_with_budget(16.0).join).to include(expected)
  end

  it "names every remedy in the warning, verbatim (#637)" do
    expect(guard_with_budget(16.0).first).to eq("raise --max-duration, pass fewer --baseline-passes, " \
                                                "or narrow the scope\n  " \
                                                "projected baseline+coverage ~15s barely fits " \
                                                "--max-duration 16s; mutants would get ~1s")
  end

  it "prices the projection the same when the coverage build is not pending (#637)" do
    expect(guard_with_budget(16.0, full_passes: 3, baseline_passes: 3).join)
      .to include("projected baseline+coverage ~15s barely fits --max-duration 16s; mutants would get ~1s")
  end

  it "stays quiet on the budget when the run clock never started (#637)" do
    expect(guard_with_budget(16.0, run_started: nil)).to be_empty
  end

  it "times the budget projection on the monotonic clock (#637)" do
    timed = Saboteur::Config.new({ "seed" => 42, "max_duration" => 16.0 }, root: @root)
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    times = [100.0, 105.0]
    allow(Process).to receive(:clock_gettime) do |*args|
      raise ArgumentError, "clock_gettime needs its clock_id" if args.empty?

      times.size > 1 ? times.shift : times.first
    end
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: timed, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: diagnostics,
                        full_passes: 3, run_started: 100.0).call
    expect(diagnostics.warnings.join).to include("barely fits")
  end

  it "stays quiet without --max-duration (#637)" do
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    allow(Process).to receive(:clock_gettime).and_return(100.0, 105.0)
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: diagnostics,
                        full_passes: 3, run_started: 100.0).call
    expect(diagnostics.warnings).to be_empty
  end

  it "announces three or more passes in the plural with the seed (#245)" do
    triple = Saboteur::Config.new({ "seed" => 42, "baseline_passes" => 3 }, root: @root)
    err = StringIO.new
    allow(supervisor).to receive(:run).and_return(response)
    diagnostics = Saboteur::Engine::Diagnostics.new(err, verbose: true)
    described_class.new(config: triple, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: diagnostics).call
    expect(err.string).to include("checking the unchanged suite 3 times (seed 42)")
  end

  it "names the coverage map build when it is the only pass left after baseline_passes 1 (#465)" do
    single = Saboteur::Config.new({ "seed" => 42, "baseline_passes" => 1 }, root: @root)
    err = StringIO.new
    allow(Process).to receive(:clock_gettime).and_return(100.0, 105.0)
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: single, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err, verbose: true),
                        full_passes: 2).call
    expect(err.string).to include("baseline check 1 took 5 s; about 5 s left for the coverage map build at that rate")
    expect(err.string).not_to include("remaining 1 full pass")
  end

  it "announces the single remaining pass in the singular" do
    err = StringIO.new
    allow(Process).to receive(:clock_gettime).and_return(100.0, 105.0)
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err, verbose: true),
                        full_passes: 2).call
    expect(err.string).to include("baseline check 1 took 5 s; about 5 s left for the remaining 1 full pass")
  end

  it "says nothing when the baseline passes are all the passes there are" do
    err = StringIO.new
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err),
                        full_passes: 1).call
    expect(err.string).not_to include("took")
  end

  it "refuses inconsistent pass/failure fields and invalid executed fields" do
    [response(passed: true, failed: ["t1"]), response(passed: false, failed: []),
     response(payload: JSON.generate(passed: true, failed: [], executed: nil))].each do |outcome|
      allow(supervisor).to receive(:run).and_return(outcome)
      expect { guard.call }.to raise_error(Saboteur::Error)
    end
  end

  it "runs two independent supervised checks with the configured suite deadline" do
    expect(supervisor).to receive(:run).twice.with(
      timeout: config["coverage_timeout"], on_tick: anything,
      label: "baseline child died during setup/run"
    ).and_return(response)
    expect(guard.call).to be_nil
  end

  it "refuses a failing baseline and names the seed and next step" do
    allow(supervisor).to receive(:run).and_return(response(passed: false, failed: ["t1"]))
    expect(Saboteur::Engine::CoverageStore).not_to receive(:new)
    expect { guard.call }.to raise_error(Saboteur::Error, /baseline check 1 failed.*seed 42.*t1.*Fix/m)
  end

  it "separates multiple failed example IDs in the baseline refusal (#581)" do
    allow(supervisor).to receive(:run).and_return(response(passed: false, failed: %w[t1 t2]))
    expect { guard.call }.to raise_error(Saboteur::Error, /the suite failed: t1, t2\./)
  end

  describe "the Minitest signature warning (#626)" do
    def write_helper(text)
      FileUtils.mkdir_p(File.join(@root, "spec"))
      File.write(File.join(@root, "spec", "spec_helper.rb"), text)
    end

    def write_failure_log(text)
      path = File.join(@root, ".saboteur", "baseline-1.log")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end

    def failing_run_output(failed: %w[t1 t2])
      diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
      allow(supervisor).to receive(:run).and_return(response(passed: false, failed: failed))
      expect do
        described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                            supervisor: supervisor, diagnostics: diagnostics).call
      end.to raise_error(Saboteur::Error, /the suite failed/)
      diagnostics.warnings.join("\n")
    end

    it "matches real require calls, wherever they sit on the line" do
      ["  require   'minitest'\n", "require 'minitest'\n", "require'minitest'\n",
       "x = 1; require 'minitest'\n", "require \"minitest/autorun\"\n"].each do |text|
        write_helper(text)
        expect(guard.send(:spec_helper_requires_minitest?)).to be(true)
      end
    end

    it "walks a deeply nested spec_helper without a stack error (#708)" do
      write_helper("X = #{'f(' * 1_500}1#{', 2)' * 1_500}\n")
      expect(guard.send(:spec_helper_requires_minitest?)).to be(false)
    end

    it "ignores minitest requires that are comments or string content (#708)" do
      ["# require 'minitest'\n", "  # require \"minitest\"\n",
       "=begin\nrequire 'minitest'\n=end\n",
       "NOTE = <<~TEXT\nrequire 'minitest'\nTEXT\n",
       "# (require 'minitest')\n"].each do |text|
        write_helper(text)
        expect(guard.send(:spec_helper_requires_minitest?)).to be(false)
      end
    end

    it "ignores receiver-qualified require calls (#708)" do
      write_helper("Foo.require 'minitest'\nKernel.require \"minitest/autorun\"\n")
      expect(guard.send(:spec_helper_requires_minitest?)).to be(false)
    end

    it "ignores non-require calls with a minitest string argument (#708)" do
      write_helper("require_relative 'minitest'\ngem \"minitest/autorun\"\nload 'minitest.rb'\n")
      expect(guard.send(:spec_helper_requires_minitest?)).to be(false)
    end

    it "collects the first string argument of each require call (#708)" do
      write_helper("require 'minitest', 'other'\n")
      expect(guard.send(:spec_helper_requires_minitest?)).to be(true)
    end

    it "tolerates a bare require with no argument list (#708)" do
      write_helper("require\nrequire 'minitest'\n")
      expect(guard.send(:spec_helper_requires_minitest?)).to be(true)
    end

    it "skips non-Node entries while walking the tree (#708)" do
      walker = Object.new
      def walker.is_a?(klass)
        klass == Prism::Node || super
      end
      node = Prism.parse("require 'minitest'\n").value
      walker.define_singleton_method(:compact_child_nodes) { [Object.new, node] }

      expect(guard.send(:require_calls, walker)).to eq(["minitest"])
    end

    [1, 2].each do |count|
      it "pins the full Minitest warning for #{count} errors" do
        write_helper("require 'minitest'\n")
        write_failure_log("NoMethodError: boom\n" * count)
        expect(failing_run_output).to eq(
          "run saboteur on an RSpec suite: it is RSpec-only, so a Minitest suite cannot be " \
          "mutation tested with it\n  " \
          "the baseline failure looks like a Minitest suite running under RSpec, not a " \
          "broken RSpec suite: the log shows #{count} NoMethodError#{'s' if count == 2} " \
          "(for example: NoMethodError: boom) and spec/spec_helper.rb requires minitest"
        )
      end
    end

    # rack-test's suite is Minitest::Spec in *_spec.rb files: it loads
    # under the RSpec integration and the baseline fails with
    # NoMethodError for Minitest-only methods, which reads like a broken
    # suite instead of the wrong framework.
    it "warns that the failure looks like Minitest, quoting the symptom and the count" do
      write_helper("require \"minitest/autorun\"\n")
      write_failure_log(<<~LOG)
        Failures:
          1) a
             NoMethodError:
               undefined method `custom_request' for #<a>
          2) b
             NoMethodError:
               undefined method `custom_request' for #<b>
      LOG
      output = failing_run_output
      expect(output).to include("looks like a Minitest suite")
      expect(output).to include("2 NoMethodErrors")
      expect(output).to include("undefined method `custom_request'")
      expect(output).to include("spec/spec_helper.rb requires minitest")
    end

    # The warning stays a warning, and the refusal keeps its shape: an
    # exit-3 baseline failure either way.
    it "still refuses the run when it warns" do
      write_helper("require \"minitest\"\n")
      write_failure_log("Failures:\n  1) a\n     NoMethodError:\n       undefined method `x' for #<a>\n")
      failing_run_output(failed: %w[t1])
    end

    # An RSpec suite can require minitest for a helper: without the
    # NoMethodError signature there is nothing to warn about.
    it "stays silent when a minitest-requiring suite fails for another reason" do
      write_helper("require \"minitest\"\n")
      write_failure_log("Failures:\n  1) a\n     expected 1, got 2\n")
      expect(failing_run_output).not_to include("Minitest")
    end

    # The signature without the helper's minitest require is just a
    # broken suite.
    it "stays silent when spec_helper does not require minitest" do
      write_helper("require \"rspec\"\n")
      write_failure_log("Failures:\n  1) a\n     NoMethodError:\n       undefined method `x' for #<a>\n")
      expect(failing_run_output).not_to include("Minitest")
    end

    it "stays silent with neither a spec_helper nor a log to read" do
      expect(failing_run_output).not_to include("Minitest")
    end

    # Message-content pins (#626 v2): the count, its pluralization and
    # the quoted symptom are the actionable parts of the warning.
    it "uses the singular for one NoMethodError (#626)" do
      write_helper("require \"minitest\"\n")
      write_failure_log("Failures:\n  1) a\n     NoMethodError:\n       undefined method `x' for #<a>\n")
      output = failing_run_output(failed: %w[t1])
      expect(output).to include("1 NoMethodError")
      expect(output).not_to include("1 NoMethodErrors")
    end

    it "quotes the first undefined-method line, not the error header (#626)" do
      write_helper("require \"minitest\"\n")
      write_failure_log(<<~LOG)
        Failures:
          1) a
             NoMethodError:
               undefined method `custom_request' for #<a>
      LOG
      expect(failing_run_output(failed: %w[t1])).to include("(for example: undefined method `custom_request' for #<a>)")
    end

    it "truncates an over-width symptom at EXCERPT_WIDTH, never quoting it whole (#626)" do
      write_helper("require \"minitest\"\n")
      long_symptom = "undefined method `x' for #<#{'y' * 210}>"
      write_failure_log(<<~LOG)
        Failures:
          1) a
             NoMethodError:
               #{long_symptom}
      LOG
      expect(failing_run_output(failed: %w[t1])).to include("(for example: #{long_symptom.slice(0, 200)})")
      expect(failing_run_output(failed: %w[t1])).not_to include(long_symptom.slice(0, 201))
    end

    it "falls back to the first NoMethodError line when no line says undefined method (#626)" do
      write_helper("require \"minitest\"\n")
      write_failure_log(<<~LOG)
        Failures:
          1) a
             NoMethodError: boom one
          2) b
             NoMethodError: boom two
      LOG
      expect(failing_run_output(failed: %w[t1 t2])).to include("(for example: NoMethodError: boom one)")
    end
  end

  describe "the failure detail printed inline" do
    def write_log(text)
      path = File.join(@root, ".saboteur", "baseline-1.log")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end

    def failure_message
      allow(supervisor).to receive(:run).and_return(response(passed: false, failed: ["t1"]))
      guard.call
    rescue Saboteur::Error => e
      e.message
    end

    it "names an outside-example error and shows its tail instead of an empty Failures section (#581)" do
      write_log("Failures:\n0 examples, 0 failures\n#{(1..12).map { |i| "filler #{i}" }.join("\n")}\n" \
                "SQLite3::BusyException: database is locked\n./spec/rails_helper.rb:41:in `before suite'\n")
      allow(supervisor).to receive(:run).and_return(response(passed: false, failed: []))
      expect { guard.call }.to raise_error(Saboteur::Error) { |error|
        expect(error.message).to include("the suite errored outside any example; see the log tail",
                                         "SQLite3::BusyException: database is locked", "./spec/rails_helper.rb:41")
        expect(error.message).not_to include("the suite failed: .", "0 examples, 0 failures", "  Failures:")
      }
    end

    it "shows the first ten lines of RSpec's Failures section, not the progress lines before it" do
      details = (1..14).map { |n| "detail #{n}" }.join("\n")
      write_log("25/100 examples finished\nFailures:\n#{details}\n100 examples, 1 failure\n")
      message = failure_message
      expect(message).to include("The log says:\n  Failures:\n  detail 1\n")
      expect(message).to include("  detail 9\n")
      expect(message).not_to include("detail 10")
      expect(message).not_to include("25/100 examples finished")
      expect(message).to include("See the full log at #{File.join(@root, '.saboteur/baseline-1.log')}")
    end

    it "shows the last ten lines when the log has no Failures section, such as a crash while loading" do
      write_log("#{(1..15).map { |n| "line #{n}" }.join("\n")}\n")
      message = failure_message
      expect(message).to include("  line 6\n  line 7").and include("  line 15\n")
      expect(message).not_to include("line 5\n")
    end

    it "cuts a very long line and skips blank lines" do
      write_log("Failures:\n\n#{'x' * 500}\n")
      message = failure_message
      expect(message).to include("  #{'x' * 200}\n")
      expect(message).not_to include("x" * 201)
      expect(message).not_to include("\n  \n")
    end

    it "prints no excerpt, and still names the log, when there is no log or it is empty" do
      expect(failure_message).not_to include("The log says")
      write_log("")
      message = failure_message
      expect(message).not_to include("The log says")
      expect(message).to include("See the full log at")
    end
  end

  it "refuses a second run that fails after the first passed" do
    allow(supervisor).to receive(:run).and_return(response, response(passed: false, failed: ["t1"]))
    expect { guard.call }.to raise_error(Saboteur::Error, /baseline check 2 failed/m)
  end

  it "rejects a missing payload independently of other error cases" do
    allow(supervisor).to receive(:run).and_return(response(payload: ""))
    expect { guard.call }.to raise_error(Saboteur::Error, /child did not report/)
  end

  # A signaled child (the OOM killer, say) can leave an empty log, which
  # looks like a suite failure; name the signal and hint the likely cause.
  it "names the signal and hints the cause when the child dies by signal" do
    _, status = Process.waitpid2(Process.fork do
      Process.kill("KILL", Process.pid)
      sleep
    end)
    allow(supervisor).to receive(:run).and_return(response.with(exit_status: status, memory_pressure: true))
    expect { guard.call }.to raise_error(Saboteur::Error, /killed by SIGKILL - possible OOM, check memory/)
  end

  def sigkill_status
    _, status = Process.waitpid2(Process.fork do
      Process.kill("KILL", Process.pid)
      sleep
    end)
    status
  end

  it "does not hint at an OOM when no memory pressure was seen" do
    allow(supervisor).to receive(:run).and_return(response.with(exit_status: sigkill_status))
    expect { guard.call }.to raise_error(Saboteur::Error) { |error|
      expect(error.message).to include("killed by SIGKILL")
      expect(error.message).not_to include("OOM")
    }
  end

  # The supervisor kills a child that closed its pipe but kept running. The
  # child already delivered a complete green result, so the check passes.
  it "accepts a complete payload when only the supervisor's own kill fired" do
    killed_after_report = response.with(exit_status: sigkill_status, supervisor_killed: true)
    allow(supervisor).to receive(:run).and_return(killed_after_report)
    expect(guard.call).to be_nil
  end

  it "still refuses a failing payload when the supervisor's own kill fired" do
    outcome = response(passed: false, failed: ["t1"]).with(exit_status: sigkill_status, supervisor_killed: true)
    allow(supervisor).to receive(:run).and_return(outcome)
    expect { guard.call }.to raise_error(Saboteur::Error, /baseline check 1 failed/)
  end

  it "does not hint at an OOM for a non-KILL signal even under memory pressure" do
    _, status = Process.waitpid2(Process.fork do
      trap("TERM", "DEFAULT")
      Process.kill("TERM", Process.pid)
      sleep
    end)
    allow(supervisor).to receive(:run).and_return(response.with(exit_status: status, memory_pressure: true))
    expect { guard.call }.to raise_error(Saboteur::Error) { |error|
      expect(error.message).to include("killed by SIGTERM")
      expect(error.message).not_to include("OOM")
    }
  end

  it "names other signals without the OOM hint" do
    _, status = Process.waitpid2(Process.fork do
      # A supervised child traps TERM; a real OOM-style kill arrives with
      # the default disposition.
      trap("TERM", "DEFAULT")
      Process.kill("TERM", Process.pid)
      sleep
    end)
    allow(supervisor).to receive(:run).and_return(response.with(exit_status: status))
    error = nil
    begin
      guard.call
    rescue Saboteur::Error => e
      error = e
    end
    expect(error.message).to include("killed by SIGTERM")
    expect(error.message).not_to include("OOM")
  end

  # The advertised case: an OOM kill mid-run leaves nothing on the pipe,
  # so the signal classification must come before the empty-payload check.
  it "names the signal even when the killed child wrote nothing" do
    _, status = Process.waitpid2(Process.fork do
      Process.kill("KILL", Process.pid)
      sleep
    end)
    empty_and_killed = response(payload: "").with(exit_status: status, memory_pressure: true)
    allow(supervisor).to receive(:run).and_return(empty_and_killed)
    expect { guard.call }.to raise_error(Saboteur::Error, /killed by SIGKILL - possible OOM, check memory/)
  end

  it "names a non-KILL signal even when the killed child wrote nothing" do
    _, status = Process.waitpid2(Process.fork do
      trap("TERM", "DEFAULT")
      Process.kill("TERM", Process.pid)
      sleep
    end)
    allow(supervisor).to receive(:run).and_return(response(payload: "").with(exit_status: status))
    expect { guard.call }.to raise_error(Saboteur::Error, /killed by SIGTERM/)
  end

  it "reports a plain non-zero exit without a signal hint" do
    _, status = Process.waitpid2(Process.fork { exit!(1) })
    allow(supervisor).to receive(:run).and_return(response.with(exit_status: status))
    expect { guard.call }.to raise_error(Saboteur::Error, /exited with status 1/)
  end

  it "accepts a successful child exit with valid payload" do
    _, status = Process.waitpid2(Process.fork { exit!(0) })
    allow(supervisor).to receive(:run).and_return(response.with(exit_status: status))
    expect { guard.call }.not_to raise_error
  end

  it "refuses a non-array execution list independently" do
    allow(supervisor).to receive(:run).and_return(response(payload: JSON.generate(passed: true, failed: [],
                                                                                  executed: nil)))
    expect { guard.call }.to raise_error(Saboteur::Error)
  end

  it "refuses a green result that omitted tests" do
    allow(supervisor).to receive(:run).and_return(response(executed: []))
    expect { guard.call }.to raise_error(Saboteur::Error, /executed tests do not match/m)
  end

  it "refuses different test order between green checks" do
    allow(integration).to receive(:all_tests).and_return(%w[t1 t2].map do |id|
      Saboteur::Integration::TestCase.new(id: id, file: "spec/a.rb")
    end)
    allow(supervisor).to receive(:run).and_return(response(executed: %w[t1 t2]), response(executed: %w[t2 t1]))
    expect { guard.call }.to raise_error(Saboteur::Error, /test order changed/m)
  end

  it "refuses an empty suite" do
    allow(integration).to receive(:all_tests).and_return([])
    expect(supervisor).not_to receive(:run)
    expect { guard.call }.to raise_error(Saboteur::Error, /no tests.*Check/m)
  end

  it "refuses malformed result fields and an unsuccessful exit or leftover children" do
    malformed = ["[]", "null", JSON.generate(passed: "yes", failed: [], executed: ["t1"]),
                 JSON.generate(passed: true, failed: nil, executed: ["t1"]),
                 JSON.generate(passed: true, failed: [], executed: [nil])]
    malformed.each do |payload|
      allow(supervisor).to receive(:run).and_return(response(payload: payload))
      expect { guard.call }.to raise_error(Saboteur::Error, /invalid.*Fix/m)
    end
    _, status = Process.waitpid2(Process.fork { exit!(1) })
    allow(supervisor).to receive(:run).and_return(response.with(exit_status: status))
    expect { guard.call }.to raise_error(Saboteur::Error, /baseline check 1.*Fix/m)
    allow(supervisor).to receive(:run).and_return(response.with(leftover_pids: [123]))
    expect { guard.call }.to raise_error(Saboteur::Error, /left 1 child process behind/)
  end

  it "names the leftover processes and skips the log excerpt, which cannot show them (#486)" do
    # The log of a passing suite holds only RSpec output: quoting its
    # "Failures:" anchor argues against the verdict, and it can never name
    # the leaked processes. The refusal carries the supervisor's pre-kill
    # notes instead.
    noted = response.with(leftover_pids: [123, 124], leftover_notes: ["123 (ruby worker.rb)", "124 (sleep 30)"])
    allow(supervisor).to receive(:run).and_return(noted)
    expect { guard.call }.to raise_error(Saboteur::Error) do |error|
      notes = "123 (ruby worker.rb), 124 (sleep 30)"
      expect(error.message).to include("the suite passed but left 2 child processes behind: #{notes}")
      expect(error.message).not_to include("The log says:")
    end
  end

  # excerpt: false only matters when the log has lines to quote: a
  # passing suite's log must not leak its RSpec output into the
  # pass-with-leaks refusal (#546).
  it "keeps the log excerpt out of the leftover refusal even when the log has lines" do
    FileUtils.mkdir_p(File.join(@root, ".saboteur"))
    File.write(File.join(@root, ".saboteur", "baseline-1.log"), "1 example, 0 failures\n")
    allow(supervisor).to receive(:run).and_return(response.with(leftover_pids: [123]))
    expect { guard.call }.to raise_error(Saboteur::Error) do |error|
      expect(error.message).to include("left 1 child process behind")
      expect(error.message).not_to include("The log says:")
    end
  end

  it "words a refusal exactly, log path and no-mutants hint included" do
    allow(supervisor).to receive(:run).and_return(response(stopped: :timeout))
    expect { guard.call }.to raise_error(
      Saboteur::Error,
      "baseline check 1 failed at seed 42: the suite stopped: timeout (deadline). " \
      "See the full log at #{File.join(@root, '.saboteur', 'baseline-1.log')}. " \
      "Fix the suite or its setup, then run saboteur again with the same seed. No mutants were started."
    )
  end

  it "names the leftover pids, comma-joined, when the supervisor took no notes" do
    allow(supervisor).to receive(:run).and_return(response.with(leftover_pids: [123, 124]))
    expect { guard.call }.to raise_error(
      Saboteur::Error,
      "baseline check 1 failed at seed 42: the suite passed but left 2 child processes behind: 123, 124. " \
      "See the full log at #{File.join(@root, '.saboteur', 'baseline-1.log')}. " \
      "Fix the suite or its setup, then run saboteur again with the same seed. No mutants were started."
    )
  end

  it "refuses supervision stops, missing payloads, malformed payloads and adapter errors" do
    [response(stopped: :timeout), response(payload: ""), response(payload: "{"),
     response(error: "boot failed")].each do |result|
      allow(supervisor).to receive(:run).and_return(result)
      expect { guard.call }.to raise_error(Saboteur::Error, /baseline check 1.*log.*Fix/m)
    end
  end

  it "scans only the first EXCERPT_SCAN_LINES for the failure section" do
    scan = described_class::EXCERPT_SCAN_LINES
    lines = (["filler"] * scan) + ["Failures:", "  1) it broke"] + (["tail"] * 20)
    FileUtils.mkdir_p(File.join(@root, ".saboteur"))
    File.binwrite(File.join(@root, ".saboteur", "baseline-1.log"), "#{lines.join("\n")}\n")
    excerpt = guard.send(:failure_excerpt, 1)
    expect(excerpt).to include("filler")
    expect(excerpt).not_to include("1) it broke")
  end

  it "leaves whitespace-only lines out of the excerpt" do
    FileUtils.mkdir_p(File.join(@root, ".saboteur"))
    File.binwrite(File.join(@root, ".saboteur", "baseline-1.log"), "boom\n   \nmore\n")
    excerpt = guard.send(:failure_excerpt, 1)
    expect(excerpt).to include("boom")
    expect(excerpt).not_to include("   \n")
  end

  # The payload is the only channel from the baseline child: every field a
  # later check reads must be present, and the fork-loss hint belongs to
  # the failing case only (#387).
  def record_into(writer, number)
    allow($stdout).to receive(:reopen)
    allow($stdout).to receive(:sync=)
    allow($stderr).to receive(:reopen)
    guard.send(:record, writer, number)
    writer
  end

  it "closes the writer after recording, also when the suite run raises" do
    result = Saboteur::Integration::RunResult.new(passed: true, failed_ids: [], executed_ids: ["t1"], runtime: 0.1)
    allow(integration).to receive(:run_baseline).with(seed: 42).and_return(result)
    expect(record_into(StringIO.new, 1)).to be_closed
    allow(integration).to receive(:run_baseline).with(seed: 42).and_raise("boom")
    expect(record_into(StringIO.new, 2)).to be_closed
  end

  it "records passed, failed and executed with no hint when the suite passes" do
    result = Saboteur::Integration::RunResult.new(passed: true, failed_ids: [], executed_ids: ["t1"], runtime: 0.1)
    allow(integration).to receive(:run_baseline).with(seed: 42).and_return(result)
    payload = JSON.parse(record_into(StringIO.new, 1).string)
    expect(payload).to include("passed" => true, "failed" => [], "executed" => ["t1"])
    expect(payload).not_to have_key("hint")
  end

  it "adds the fork-loss hint to the payload when the suite fails (#387)" do
    allow(Saboteur::Frameworks::SqliteMemoryDatabase).to receive(:fork_loss_hint).and_return("HINT TEXT")
    result = Saboteur::Integration::RunResult.new(passed: false, failed_ids: ["t1"], executed_ids: ["t1"], runtime: 0.1)
    allow(integration).to receive(:run_baseline).with(seed: 42).and_return(result)
    payload = JSON.parse(record_into(StringIO.new, 1).string)
    expect(payload).to include("passed" => false, "failed" => ["t1"], "hint" => "HINT TEXT")
  end

  it "passes the child error and its fork-loss hint into the refusal (#387)" do
    payload = JSON.generate("error" => "SQLite3::SQLException: no such table",
                            "hint" => "reconnect in an after_fork hook")
    allow(supervisor).to receive(:run).and_return(response(payload: payload))
    expect { guard.call }.to raise_error(Saboteur::Error, /no such table.*reconnect in an after_fork hook/)
  end

  it "names the failed tests with the fork-loss hint when the unchanged suite fails (#387)" do
    payload = JSON.generate(passed: false, failed: ["t1"], executed: ["t1"], hint: "reconnect in an after_fork hook")
    allow(supervisor).to receive(:run).and_return(response(payload: payload))
    expect { guard.call }.to raise_error(Saboteur::Error, /the suite failed: t1\. reconnect in an after_fork hook/)
  end

  it "appends nothing when the child reported no hint" do
    payload = JSON.generate(passed: false, failed: ["t1"], executed: ["t1"])
    allow(supervisor).to receive(:run).and_return(response(payload: payload))
    expect { guard.call }.to raise_error(Saboteur::Error, /the suite failed: t1\. See the full log/)
  end
end

RSpec.describe Saboteur::Engine::BaselineGuard, "mutation hook compatibility" do
  it "does not pass nil to mutation-specific before_fork callbacks" do
    Dir.mktmpdir do |root|
      hooks = Saboteur::Hooks.new
      hooks.register(:before_fork, &:edits)
      tests = [Saboteur::Integration::TestCase.new(id: "t1", file: "a.rb")]
      adapter = double("adapter", test_files: [], all_tests: tests)
      supervisor = instance_double(Saboteur::Execution::Supervisor)
      payload = JSON.generate(passed: true, failed: [], executed: ["t1"])
      outcome = Saboteur::Execution::Supervisor::Result.new(payload: payload, exit_status: nil, stopped_by: nil,
                                                            detail: nil, runtime: 0.1, leftover_pids: [])
      allow(supervisor).to receive(:run).and_return(outcome)
      guard = described_class.new(config: Saboteur::Config.new({}, root: root), integration: adapter, hooks: hooks,
                                  supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new))
      expect { guard.call }.not_to raise_error
    end
  end
end
