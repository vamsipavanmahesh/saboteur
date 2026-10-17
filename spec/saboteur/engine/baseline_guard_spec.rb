# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::BaselineGuard do
  around do |example|
    Dir.mktmpdir { |root| @root = root and example.run }
  end

  let(:config) { Saboteur::Config.new({ "seed" => 42 }, root: @root) }
  let(:integration) { double("adapter", all_tests: [Saboteur::Integration::TestCase.new(id: "t1", file: "spec/a.rb")]) }
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
    expect(diagnostics).to have_received(:inform).with("checking the unchanged suite twice (seed 42)")
  end

  it "runs a single check and notes the tradeoff when baseline_passes is 1 (#55)" do
    single = Saboteur::Config.new({ "seed" => 42, "baseline_passes" => 1 }, root: @root)
    err = StringIO.new
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: single, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err)).call
    expect(supervisor).to have_received(:run).once
    expect(err.string).to include("checking the unchanged suite once (seed 42)")
    expect(err.string).to include("order stability between passes is not checked (baseline_passes: 1)")
  end

  it "estimates the remaining full passes once the first baseline pass is timed (#260)" do
    err = StringIO.new
    allow(Process).to receive(:clock_gettime).and_return(100.0, 105.0)
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err),
                        full_passes: 3).call
    expect(err.string.scan(/baseline check \d+ took/).size).to eq(1)
    expect(err.string).to include("baseline check 1 took 5 s; about 10 s left for the remaining 2 full passes " \
                                  "at that rate")
  end

  it "announces three or more passes in the plural with the seed (#245)" do
    triple = Saboteur::Config.new({ "seed" => 42, "baseline_passes" => 3 }, root: @root)
    err = StringIO.new
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: triple, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err)).call
    expect(err.string).to include("checking the unchanged suite 3 times (seed 42)")
  end

  it "announces the single remaining pass in the singular" do
    err = StringIO.new
    allow(Process).to receive(:clock_gettime).and_return(100.0, 105.0)
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err),
                        full_passes: 2).call
    expect(err.string).to include("baseline check 1 took 5 s; about 5 s left for the remaining 1 full pass " \
                                  "at that rate")
  end

  it "names the coverage map build as the remaining pass once the baseline is done (#465)" do
    single = Saboteur::Config.new({ "seed" => 42, "baseline_passes" => 1 }, root: @root)
    err = StringIO.new
    allow(Process).to receive(:clock_gettime).and_return(100.0, 105.0)
    allow(supervisor).to receive(:run).and_return(response)
    described_class.new(config: single, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err),
                        full_passes: 2).call
    expect(err.string).to include("baseline check 1 took 5 s; the baseline is done, " \
                                  "the remaining full pass is the coverage map build (about 5 s at that rate)")
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
    expect { guard.call }.to raise_error(Saboteur::Error, /the suite left child processes behind/)
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
      adapter = double("adapter", all_tests: [Saboteur::Integration::TestCase.new(id: "t1", file: "a.rb")])
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
