# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::BaselineGuard, "pins" do
  around do |example|
    Dir.mktmpdir { |root| @root = root and example.run }
  end

  let(:config) { Saboteur::Config.new({ "seed" => 42 }, root: @root) }
  let(:test_case) { Saboteur::Integration::TestCase.new(id: "t1", file: "spec/a.rb") }
  let(:test_files) { [] }
  let(:integration) { double("adapter", test_files: test_files, all_tests: [test_case]) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:between) { nil }
  let(:cap) { nil }
  let(:guard) do
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: diagnostics, between_passes: between,
                        timeout_cap: cap)
  end
  let(:log_dir) { File.join(@root, ".saboteur") }

  def response(passed: true, executed: ["t1"], failed: [], stopped: nil, payload: nil)
    contents = payload || JSON.generate(passed: passed, executed: executed, failed: failed)
    Saboteur::Execution::Supervisor::Result.new(payload: contents, exit_status: nil, stopped_by: stopped,
                                                detail: "deadline", runtime: 0.1, leftover_pids: [])
  end

  def refusal_of(guard)
    guard.call
    nil
  rescue Saboteur::Error => e
    e.message
  end

  describe "counting and skipping passes" do
    it "starts at zero and counts each completed pass" do
      allow(supervisor).to receive(:run).and_return(response)
      expect(guard.completed_passes).to eq(0)
      guard.call
      expect(guard.completed_passes).to eq(2)
    end

    context "with a spent budget" do
      let(:between) { -> { true } }

      it "runs no pass at all" do
        allow(supervisor).to receive(:run)
        guard.call
        expect(supervisor).not_to have_received(:run)
        expect(guard.completed_passes).to eq(0)
      end
    end

    context "with a budget that is not spent" do
      let(:between) { -> { false } }

      it "runs every pass" do
        allow(supervisor).to receive(:run).and_return(response)
        guard.call
        expect(supervisor).to have_received(:run).twice
        expect(guard.completed_passes).to eq(2)
      end
    end

    context "with a budget that runs out after the first pass" do
      let(:between) do
        calls = 0
        -> { (calls += 1) > 1 }
      end

      it "stops after one completed pass" do
        allow(supervisor).to receive(:run).and_return(response)
        guard.call
        expect(supervisor).to have_received(:run).once
        expect(guard.completed_passes).to eq(1)
      end
    end
  end

  describe "the pass number in refusals" do
    it "names pass 1 for a first-pass failure and pass 2 for a changed order" do
      allow(supervisor).to receive(:run).and_return(response(passed: false, failed: ["t1"]))
      expect(refusal_of(guard)).to start_with("baseline check 1 failed at seed 42: the suite failed: t1. ")
    end

    it "names pass 2 and the order reason in order" do
      one = Saboteur::Integration::TestCase.new(id: "t2", file: "spec/a.rb")
      allow(integration).to receive(:all_tests).and_return([test_case, one])
      allow(supervisor).to receive(:run).and_return(response(executed: %w[t1 t2]), response(executed: %w[t2 t1]))
      expect(refusal_of(guard)).to start_with(
        "baseline check 2 failed at seed 42: test order changed between baseline checks. "
      )
    end
  end

  describe "the phase timeout cap" do
    let(:cap) { ->(timeout) { timeout / 2 } }

    it "hands the supervisor the capped timeout" do
      allow(supervisor).to receive(:run).and_return(response)
      guard.call
      expect(supervisor).to have_received(:run).with(hash_including(timeout: 1800.0)).twice
    end

    it "raises the budget error when the cap, not the suite, ended a pass" do
      allow(supervisor).to receive(:run).and_return(response(stopped: :timeout, payload: ""))
      expect { guard.call }.to raise_error(
        Saboteur::BudgetPhaseTimeout,
        "the --max-duration budget stopped baseline check 1 (admitted 1800.0s of the 3600.0s phase timeout)"
      )
    end

    it "does not raise the budget error for a pass that finished normally" do
      allow(supervisor).to receive(:run).and_return(response)
      expect { guard.call }.not_to raise_error
    end

    it "refuses as a stopped suite, not a budget stop, for another stop reason" do
      allow(supervisor).to receive(:run).and_return(response(stopped: :memory, payload: ""))
      expect(refusal_of(guard)).to start_with("baseline check 1 failed at seed 42: the suite stopped: memory ")
    end
  end

  describe "without a cap" do
    it "refuses a timeout at the full phase timeout as a stopped suite, not a budget stop" do
      allow(supervisor).to receive(:run).and_return(response(stopped: :timeout, payload: ""))
      expect(refusal_of(guard)).to start_with(
        "baseline check 1 failed at seed 42: the suite stopped: timeout (deadline). "
      )
    end
  end

  describe "the heartbeat label" do
    it "names the check number" do
      heartbeat = instance_double(Saboteur::Engine::Diagnostics::ProgressHeartbeat, tick: nil)
      allow(heartbeat).to receive(:watch).and_return(heartbeat)
      allow(diagnostics).to receive(:progress_heartbeat).and_return(heartbeat)
      allow(supervisor).to receive(:run).and_return(response)
      guard.call
      expect(diagnostics).to have_received(:progress_heartbeat).with("baseline check 1")
      expect(diagnostics).to have_received(:progress_heartbeat).with("baseline check 2")
    end
  end

  describe "split checks" do
    let(:test_files) { %w[spec/a_spec.rb spec/b_spec.rb] }
    let(:config) { Saboteur::Config.new({ "seed" => 42, "coverage_parts" => 2 }, root: @root) }

    it "runs the parts together when there are two" do
      other = Saboteur::Integration::TestCase.new(id: "t2", file: "spec/b_spec.rb")
      allow(integration).to receive(:all_tests).and_return([test_case, other])
      allow(supervisor).to receive(:run_many).and_return([response, response(executed: ["t2"])])
      allow(supervisor).to receive(:run)
      guard.call
      expect(supervisor).to have_received(:run_many).with(2, hash_including(timeout: 3600.0)).twice
      expect(supervisor).not_to have_received(:run)
    end

    context "with one spec file" do
      let(:test_files) { %w[spec/a_spec.rb] }

      it "runs the ordinary single check" do
        allow(supervisor).to receive(:run).and_return(response)
        allow(supervisor).to receive(:run_many)
        guard.call
        expect(supervisor).to have_received(:run).twice
        expect(supervisor).not_to have_received(:run_many)
      end
    end
  end

  describe "reading the child's result" do
    def refusal_for(payload)
      allow(supervisor).to receive(:run).and_return(response(payload: payload))
      refusal_of(guard)
    end

    it "names an invalid JSON reply" do
      expect(refusal_for("{nope"))
        .to start_with("baseline check 1 failed at seed 42: the child reported invalid JSON. ")
    end

    it "names a reply that is not an object" do
      expect(refusal_for("[1]"))
        .to start_with("baseline check 1 failed at seed 42: the child reported an invalid result. ")
    end

    it "names the child's own error, with its hint" do
      expect(refusal_for(JSON.generate(error: "Boom: x", hint: "HINT")))
        .to start_with("baseline check 1 failed at seed 42: Boom: x. HINT. ")
    end

    it "names invalid test results, including executed ids that are not strings" do
      expect(refusal_for(JSON.generate(passed: true, failed: [], executed: [1])))
        .to start_with("baseline check 1 failed at seed 42: the child reported invalid test results. ")
    end
  end

  describe "#record" do
    let(:writer) { StringIO.new }

    before do
      allow($stdout).to receive(:reopen)
      allow($stdout).to receive(:sync=)
      allow($stderr).to receive(:reopen)
      allow(Saboteur::Frameworks::SqliteMemoryDatabase).to receive(:fork_loss_hint).and_return("HINT")
    end

    it "runs only the given files for a part and logs to that part's file" do
      result = Saboteur::Integration::RunResult.new(passed: true, failed_ids: [], executed_ids: ["t1"], runtime: 0.1)
      allow(integration).to receive(:run_baseline).and_return(result)
      guard.send(:record, writer, 1, files: ["spec/a_spec.rb"], part: 1)
      expect(integration).to have_received(:run_baseline).with(seed: 42, files: ["spec/a_spec.rb"])
      expect($stdout).to have_received(:reopen).with(File.join(log_dir, "baseline-1-part-2.log"), "w")
    end

    it "adds the fork-loss hint to a failed result" do
      result = Saboteur::Integration::RunResult.new(passed: false, failed_ids: ["t1"], executed_ids: ["t1"],
                                                    runtime: 0.1)
      allow(integration).to receive(:run_baseline).and_return(result)
      guard.send(:record, writer, 1)
      expect(JSON.parse(writer.string)).to eq("passed" => false, "failed" => ["t1"], "executed" => ["t1"],
                                              "hint" => "HINT")
    end

    it "reports an error from the run as class and message, with the hint" do
      allow(integration).to receive(:run_baseline).and_raise(ArgumentError, "boom")
      guard.send(:record, writer, 1)
      expect(JSON.parse(writer.string)).to eq("error" => "ArgumentError: boom", "hint" => "HINT")
    end
  end

  describe "the log of a split check" do
    it "names the part's log in the refusal" do
      allow(supervisor).to receive(:run).and_return(response)
      message = nil
      begin
        guard.send(:settled, 1, response(stopped: :timeout, payload: ""), 3600.0, part: 1)
      rescue Saboteur::Error => e
        message = e.message
      end
      expect(message).to include("See the full log at #{File.join(log_dir, 'baseline-1-part-2.log')}.")
    end
  end

  describe "the log excerpt" do
    it "keeps the excerpt valid text when the log holds invalid bytes" do
      FileUtils.mkdir_p(log_dir)
      File.binwrite(File.join(log_dir, "baseline-1.log"), "bad \xFF byte\nsecond\n")
      allow(supervisor).to receive(:run).and_return(response(passed: false, failed: ["t1"]))
      message = refusal_of(guard)
      expect(message.valid_encoding?).to be(true)
      expect(message).to include("The log says:\n  bad ")
    end

    it "warns nothing about Minitest when the project has no spec_helper" do
      FileUtils.mkdir_p(log_dir)
      File.write(File.join(log_dir, "baseline-1.log"), "NoMethodError: undefined method 'x'\n")
      allow(supervisor).to receive(:run).and_return(response(passed: false, failed: ["t1"]))
      expect(diagnostics).not_to receive(:warn)
      expect(refusal_of(guard)).to include("baseline check 1 failed")
    end
  end
end
