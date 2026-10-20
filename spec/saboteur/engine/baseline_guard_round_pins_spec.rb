# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::BaselineGuard, "budget message pins" do
  around do |example|
    Dir.mktmpdir { |root| @root = root and example.run }
  end

  let(:config) { Saboteur::Config.new({ "seed" => 42 }, root: @root) }
  let(:integration) do
    double("adapter", test_files: [], all_tests: [Saboteur::Integration::TestCase.new(id: "t1", file: "spec/a.rb")])
  end
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }
  let(:guard) do
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                        timeout_cap: ->(_timeout) { 12.3456 })
  end

  it "rounds the admitted seconds to one decimal in the budget stop message" do
    stopped = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :timeout,
                                                          detail: "deadline", runtime: 0.1, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(stopped)
    expect { guard.call }.to raise_error(
      Saboteur::BudgetPhaseTimeout,
      "the --max-duration budget stopped baseline check 1 (admitted 12.3s of the 3600.0s phase timeout)"
    )
  end
end
