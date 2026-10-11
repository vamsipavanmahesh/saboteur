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
