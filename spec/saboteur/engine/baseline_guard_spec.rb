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
    expect(diagnostics).to receive(:inform).with("checking the unchanged suite twice (seed 42)")
    expect(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap).twice
    allow(supervisor).to receive(:run).and_return(response)
    checked = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                  supervisor: supervisor, diagnostics: diagnostics)
    checked.call
    expect(checked.send(:log_path, 1)).to eq(File.join(@root, ".saboteur/baseline-1.log"))
  end

  it "refuses inconsistent pass/failure fields and invalid executed fields" do
    [response(passed: true, failed: ["t1"]), response(passed: false, failed: []),
     response(payload: JSON.generate(passed: true, failed: [], executed: nil))].each do |outcome|
      allow(supervisor).to receive(:run).and_return(outcome)
      expect { guard.call }.to raise_error(Saboteur::Error)
    end
  end

  it "runs two independent supervised checks with the configured suite deadline" do
    expect(supervisor).to receive(:run).with(timeout: config["coverage_timeout"]).twice.and_return(response)
    expect(guard.call).to be_nil
  end

  it "refuses a failing baseline and names the seed and next step" do
    allow(supervisor).to receive(:run).and_return(response(passed: false, failed: ["t1"]))
    expect(Saboteur::Engine::CoverageStore).not_to receive(:new)
    expect { guard.call }.to raise_error(Saboteur::Error, /baseline check 1 failed.*seed 42.*t1.*Fix/m)
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
    allow(supervisor).to receive(:run).and_return(response.with(exit_status: status))
    expect { guard.call }.to raise_error(Saboteur::Error, /killed by SIGKILL - possible OOM, check memory/)
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
    [response.with(exit_status: status), response.with(leftover_pids: [123])].each do |result|
      allow(supervisor).to receive(:run).and_return(result)
      expect { guard.call }.to raise_error(Saboteur::Error, /baseline check 1.*Fix/m)
    end
  end

  it "refuses supervision stops, missing payloads, malformed payloads and adapter errors" do
    [response(stopped: :timeout), response(payload: ""), response(payload: "{"),
     response(error: "boot failed")].each do |result|
      allow(supervisor).to receive(:run).and_return(result)
      expect { guard.call }.to raise_error(Saboteur::Error, /baseline check 1.*log.*Fix/m)
    end
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
