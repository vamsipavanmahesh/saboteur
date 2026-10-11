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

  it "refuses supervision stops, missing payloads, malformed payloads and adapter errors" do
    [response(stopped: :timeout), response(payload: ""), response(payload: "{"),
     response(error: "boot failed")].each do |result|
      allow(supervisor).to receive(:run).and_return(result)
      expect { guard.call }.to raise_error(Saboteur::Error, /baseline check 1.*log.*Fix/m)
    end
  end
end
