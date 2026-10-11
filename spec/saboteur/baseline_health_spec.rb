# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/baseline_health"

RSpec.describe Saboteur::BaselineHealth do
  let(:config) { Saboteur::Config.new }
  let(:integration) { instance_double(Saboteur::Integration::Base, all_tests: [Saboteur::Integration::TestCase.new(id: "a", file: "spec/a.rb")]) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }

  def response(passed: true, executed: ["a"])
    instance_double(Saboteur::Execution::Supervisor::Result, stopped_by: nil,
                                                             payload: JSON.generate(passed: passed, executed: executed),
                                                             exit_status: nil, leftover_pids: [])
  end

  it "requires two green runs with the same executed sequence" do
    allow(supervisor).to receive(:run).and_return(response, response)
    expect(described_class.new(config, integration: integration, supervisor: supervisor).call).to eq(["a"])
    expect(supervisor).to have_received(:run).with(timeout: 300.0).twice
  end

  it "rejects a red baseline" do
    allow(supervisor).to receive(:run).and_return(response(passed: false))
    expect { described_class.new(config, integration: integration, supervisor: supervisor).call }
      .to raise_error(Saboteur::Error, /baseline run 1 failed/)
  end

  it "rejects an incomplete green run" do
    allow(supervisor).to receive(:run).and_return(response(executed: []))
    expect { described_class.new(config, integration: integration, supervisor: supervisor).call }
      .to raise_error(Saboteur::Error, /did not execute every/)
  end

  it "rejects different order on the second run" do
    tests = %w[a b].map { |id| Saboteur::Integration::TestCase.new(id: id, file: "spec/a.rb") }
    allow(integration).to receive(:all_tests).and_return(tests)
    allow(supervisor).to receive(:run).and_return(response(executed: %w[a b]), response(executed: %w[b a]))
    expect { described_class.new(config, integration: integration, supervisor: supervisor).call }
      .to raise_error(Saboteur::Error, /different test order/)
  end

  it "refuses to call an empty suite healthy" do
    allow(integration).to receive(:all_tests).and_return([])
    expect { described_class.new(config, integration: integration, supervisor: supervisor).call }
      .to raise_error(Saboteur::Error, /no tests/)
    expect(supervisor).not_to receive(:run)
  end
end

RSpec.describe Saboteur::BaselineHealth, "stopped checks" do
  it "reports supervised resource and deadline stops" do
    config = Saboteur::Config.new
    integration = instance_double(Saboteur::Integration::Base,
                                  all_tests: [Saboteur::Integration::TestCase.new(id: "a", file: "a.rb")])
    supervisor = instance_double(Saboteur::Execution::Supervisor)
    result = instance_double(Saboteur::Execution::Supervisor::Result, stopped_by: :timeout, detail: "deadline")
    allow(supervisor).to receive(:run).and_return(result)
    expect { described_class.new(config, integration: integration, supervisor: supervisor).call }
      .to raise_error(Saboteur::Error, /stopped: deadline/)
  end
end

RSpec.describe Saboteur::BaselineHealth, "bad child evidence" do
  let(:integration) do
    instance_double(Saboteur::Integration::Base,
                    all_tests: [Saboteur::Integration::TestCase.new(id: "a", file: "a.rb")])
  end
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }

  def check(payload:, exit_status: nil, leftover_pids: [])
    result = instance_double(Saboteur::Execution::Supervisor::Result, stopped_by: nil,
                                                                      payload: payload, exit_status: exit_status,
                                                                      leftover_pids: leftover_pids)
    allow(supervisor).to receive(:run).and_return(result)
    described_class.new(Saboteur::Config.new, integration: integration, supervisor: supervisor).call
  end

  it "rejects missing payload" do
    expect { check(payload: "") }.to raise_error(Saboteur::Error, /without a result/)
  end

  it "rejects malformed and non-object payloads" do
    ["{", "[]", "null"].each do |payload|
      expect { check(payload: payload) }.to raise_error(Saboteur::Error, /invalid result/)
    end
  end

  it "rejects a nonzero child exit even with green evidence" do
    pid = fork { exit! 7 }
    _, status = Process.wait2(pid)
    expect { check(payload: JSON.generate(passed: true, executed: ["a"]), exit_status: status) }
      .to raise_error(Saboteur::Error, /exited unsuccessfully/)
  end

  it "rejects leftover processes" do
    expect { check(payload: JSON.generate(passed: true, executed: ["a"]), leftover_pids: [123]) }
      .to raise_error(Saboteur::Error, /left processes/)
  end
end
