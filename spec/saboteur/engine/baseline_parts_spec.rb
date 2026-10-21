# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::BaselineParts do
  around do |example|
    Dir.mktmpdir { |root| @root = root and example.run }
  end

  let(:settings) { { "seed" => 42, "baseline_passes" => 1, "coverage_parts" => 2 } }
  let(:config) { Saboteur::Config.new(settings, root: @root) }
  let(:tests) do
    [Saboteur::Integration::TestCase.new(id: "a1", file: "spec/a_spec.rb"),
     Saboteur::Integration::TestCase.new(id: "b1", file: "spec/b_spec.rb")]
  end
  let(:integration) do
    double("adapter", all_tests: tests, test_files: %w[spec/a_spec.rb spec/b_spec.rb])
  end
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }
  let(:out) { StringIO.new }
  let(:guard) do
    described_class_guard = Saboteur::Engine::BaselineGuard
    described_class_guard.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                              supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(out))
  end

  def response(passed: true, executed: [], failed: [], stopped: nil, hint: nil)
    Saboteur::Execution::Supervisor::Result.new(payload: JSON.generate({ passed: passed, executed: executed,
                                                                         failed: failed, hint: hint }.compact),
                                                exit_status: nil, stopped_by: stopped, detail: "deadline",
                                                runtime: 0.1, leftover_pids: [])
  end

  def parts_answer(*results)
    allow(supervisor).to receive(:run_many).and_return(results)
  end

  it "runs the partitions the coverage build uses and accepts when their union is the loaded suite" do
    parts_answer(response(executed: ["a1"]), response(executed: ["b1"]))
    guard.call
    expect(supervisor).to have_received(:run_many).with(2, hash_including(label: /baseline child died/))
    expect(guard.completed_passes).to eq(1)
  end

  it "gives each part the files of its partition, its own log and TEST_ENV_NUMBER" do
    seen = []
    allow(supervisor).to receive(:run_many) do |count, **_, &block|
      Array.new(count) do |slot|
        old = ENV.fetch("TEST_ENV_NUMBER", nil)
        writer = StringIO.new
        allow(guard).to receive(:record) do |given, number, **kw|
          seen << [kw, ENV.fetch("TEST_ENV_NUMBER", nil)]
          expect([given, number]).to eq([writer, 1])
        end
        block.call(writer, slot)
        ENV["TEST_ENV_NUMBER"] = old
        response(executed: [tests[slot].id])
      end
    end
    guard.call
    files = seen.map { |kw, _| kw[:files] }
    expect(files.flatten.sort).to eq(%w[spec/a_spec.rb spec/b_spec.rb])
    expect(seen.map(&:last)).to eq(["", "2"])
    expect(seen.map { |kw, _| kw[:part] }).to eq([0, 1])
  end

  it "refuses when a part fails, naming the failing test, that part's log and its hint" do
    parts_answer(response(executed: ["a1"]),
                 response(passed: false, executed: ["b1"], failed: ["b1"], hint: "try X"))
    expect { guard.call }.to raise_error(Saboteur::Error, /b1.*try X.*baseline-1-part-2\.log/m)
  end

  it "refuses a part that reports failures although it says it passed, and one that says it failed with none" do
    parts_answer(response(executed: ["a1"]), response(passed: true, executed: ["b1"], failed: ["b1"]))
    expect { guard.call }.to raise_error(Saboteur::Error, /b1/)
    parts_answer(response(executed: ["a1"]), response(passed: false, executed: ["b1"]))
    expect { guard.call }.to raise_error(Saboteur::Error, /baseline check 1 failed/)
  end

  it "refuses when the first part fails and names the first part's log" do
    parts_answer(response(passed: false, executed: ["a1"], failed: ["a1"]), response(executed: ["b1"]))
    expect { guard.call }.to raise_error(Saboteur::Error, /baseline-1-part-1\.log/)
  end

  it "refuses when the parts together miss a loaded test" do
    parts_answer(response(executed: ["a1"]), response(executed: []))
    expect { guard.call }.to raise_error(Saboteur::Error, /do not match the loaded suite/)
  end

  it "refuses when a test runs twice across the parts" do
    parts_answer(response(executed: %w[a1 b1]), response(executed: ["b1"]))
    expect { guard.call }.to raise_error(Saboteur::Error, /do not match the loaded suite/)
  end

  it "refuses a part that was stopped, naming that part's log" do
    parts_answer(response(executed: ["a1"]), response(stopped: :timeout))
    expect { guard.call }.to raise_error(Saboteur::Error, /baseline-1-part-2\.log/)
  end

  it "prepares the heap, watches the first part's log and ticks the heartbeat" do
    heartbeat = instance_double(Saboteur::Engine::Diagnostics::ProgressHeartbeat, tick: nil)
    diagnostics = instance_double(Saboteur::Engine::Diagnostics, inform: nil, detail: nil)
    allow(diagnostics).to receive(:progress_heartbeat).and_return(heartbeat)
    allow(heartbeat).to receive(:watch).and_return(heartbeat)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
    ticks = nil
    allow(supervisor).to receive(:run_many) do |_count, on_tick:, **|
      ticks = on_tick
      [response(executed: ["a1"]), response(executed: ["b1"])]
    end
    watched = Saboteur::Engine::BaselineGuard.new(config: config, integration: integration,
                                                  hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                                  diagnostics: diagnostics)
    watched.call
    expect(Saboteur::Execution::ForkReadiness).to have_received(:prepare_heap).once
    expect(diagnostics).to have_received(:progress_heartbeat).with("baseline check 1 (2 parts)")
    expect(heartbeat).to have_received(:watch).with(File.join(@root, ".saboteur/baseline-1-part-1.log"))
    expect(ticks).to eq(heartbeat.method(:tick))
  end

  it "records a part's examples into its own log, running only its files" do
    result = Saboteur::Integration::RunResult.new(passed: true, failed_ids: [], executed_ids: ["b1"], runtime: 0.1)
    expect(integration).to receive(:run_baseline).with(seed: 42, files: ["spec/b_spec.rb"]).and_return(result)
    expect($stdout).to receive(:reopen).with(File.join(@root, ".saboteur/baseline-1-part-2.log"), "w")
    allow($stdout).to receive(:sync=)
    allow($stderr).to receive(:reopen)
    writer = StringIO.new
    guard.send(:record, writer, 1, files: ["spec/b_spec.rb"], part: 1)
    expect(JSON.parse(writer.string)["executed"]).to eq(["b1"])
  end

  it "keeps the single check when coverage_parts is 1" do
    allow(supervisor).to receive(:run).and_return(response(executed: %w[a1 b1]))
    one = Saboteur::Config.new(settings.merge("coverage_parts" => 1), root: @root)
    single = Saboteur::Engine::BaselineGuard.new(config: one, integration: integration, hooks: Saboteur::Hooks.new,
                                                 supervisor: supervisor,
                                                 diagnostics: Saboteur::Engine::Diagnostics.new(out))
    single.call
    expect(supervisor).to have_received(:run)
  end

  it "keeps the single check when the suite is a single spec file" do
    allow(integration).to receive(:test_files).and_return(["spec/a_spec.rb"])
    allow(supervisor).to receive(:run).and_return(response(executed: %w[a1 b1]))
    guard.call
    expect(supervisor).to have_received(:run)
  end
end
