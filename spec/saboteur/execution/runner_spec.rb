# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

# What the fake suite reports, per mode, for the modes that return.
RUNNER_SPEC_RESULTS = {
  "pass" => ->(ids) { { passed: true, failed_ids: [], executed_ids: ids } },
  "title" => ->(ids) { { passed: true, failed_ids: [], executed_ids: ids } },
  "fail" => lambda { |ids|
    { passed: false, failed_ids: [ids.first], executed_ids: [ids.first],
      failure_classes: { ids.first => "RSpec::Expectations::ExpectationNotMetError" },
      failure_messages: { ids.first => "expected: 2 got: 3" } }
  },
  "crash" => lambda { |ids|
    { passed: false, failed_ids: [ids.first], executed_ids: [ids.first],
      failure_classes: { ids.first => "NoMethodError" } }
  },
  "partial" => ->(ids) { { passed: true, failed_ids: [], executed_ids: ids.first(1) } },
  "foreign" => ->(_ids) { { passed: false, failed_ids: ["other"], executed_ids: ["other"] } }
}.freeze

RSpec.describe Saboteur::Execution::Runner do
  # The "method text" doubles as an instruction for the fake integration, so
  # each example can make the child pass, fail, hang or crash.
  let(:reevaluator) do
    Class.new do
      attr_reader :mode

      def call(_subject, text)
        raise "boom while evaluating" if text == "raise_on_eval"

        Process.kill("KILL", Process.pid) if text == "die_on_eval"

        @mode = text
      end
    end.new
  end

  let(:integration) do
    reeval = reevaluator
    dir = tmpdir
    Class.new do
      define_method(:run) do |ids|
        mode = reeval.mode
        File.write(File.join(dir, "title"), `ps -o command= -p #{Process.pid}`.strip) if mode == "title"
        case mode
        when "exit" then exit(1)
        when "die" then Process.kill("KILL", Process.pid)
        when "hang"
          File.write(File.join(dir, "grandchild.pid"), Process.spawn("sleep", "300").to_s)
          loop { sleep 0.01 }
        else Saboteur::Integration::RunResult.new(runtime: 0.01, **RUNNER_SPEC_RESULTS.fetch(mode).call(ids))
        end
      end
    end.new
  end

  let(:tmpdir) { Dir.mktmpdir("saboteur-runner-") }
  let(:hooks) { Saboteur::Hooks.new }
  let(:runner) { described_class.new(integration:, reevaluator:, hooks:, log_dir: tmpdir) }
  let(:subject_stub) { Struct.new(:id).new("Stub#run") }

  after { FileUtils.rm_rf(tmpdir) }

  def run_mode(text, timeout: 5, tests: %w[t1 t2])
    runner.run(subject: subject_stub, text: text, test_ids: tests, timeout: timeout)
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  it "names the mutant in the child's process title, so ps shows what is running" do
    subject_with_id = Struct.new(:id).new("Shop::Cart#total")
    edit = Saboteur::MutationSource::Edit.new(file: "f.rb", start_byte: 0, end_byte: 1, replacement: "x")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: "Shop::Cart#total", operator: "comparison",
                                                      edits: [edit])
    runner.run(subject: subject_with_id, text: "title", test_ids: ["t1"], timeout: 5, mutation: mutation)
    expect(File.read(File.join(tmpdir, "title"))).to eq("saboteur: Shop::Cart#total comparison")
  end

  it "names a neutral check in the child's process title" do
    runner.run(subject: Struct.new(:id).new("Shop::Cart#total"), text: "title", test_ids: ["t1"], timeout: 5)
    expect(File.read(File.join(tmpdir, "title"))).to eq("saboteur: Shop::Cart#total neutral check")
  end

  it "reports survived when every requested test ran and passed" do
    expect(run_mode("pass").status).to eq(:survived)
  end

  it "reports killed with the failing test ids" do
    outcome = run_mode("fail")
    expect([outcome.status, outcome.failed_ids]).to eq([:killed, ["t1"]])
  end

  it "keeps the killing test's failure message" do
    expect(run_mode("fail").message).to eq("expected: 2 got: 3")
  end

  it "records why the killing test failed: an assertion or a crash" do
    expect(run_mode("fail").kill_cause).to eq("assertion")
    expect(run_mode("crash").kill_cause).to eq("NoMethodError")
  end

  it "reports a stop at the memory or process cap as resource_limit, not timeout" do
    supervisor = instance_double(Saboteur::Execution::Supervisor)
    stop = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :memory,
                                                       detail: "process tree grew by 3000 MB (limit 2048 MB)",
                                                       runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(stop)
    capped = described_class.new(integration:, reevaluator:, hooks:, log_dir: tmpdir, supervisor:)
    outcome = capped.run(subject: subject_stub, text: "pass", test_ids: ["t1"], timeout: 5)
    expect([outcome.status, outcome.message]).to eq([:resource_limit, "process tree grew by 3000 MB (limit 2048 MB)"])
  end

  it "counts a test calling exit as killed" do
    expect(run_mode("exit").status).to eq(:killed)
  end

  it "reports error, never survived, when fewer tests ran than requested" do
    outcome = run_mode("partial")
    expect([outcome.status, outcome.message]).to eq([:error, "executed 1 of 2 requested tests"])
  end

  it "reports error when a test that was not requested failed" do
    expect(run_mode("foreign").status).to eq(:error)
  end

  it "reports error, not killed, when the child dies while tests run" do
    outcome = run_mode("die")
    expect(outcome.status).to eq(:error)
    expect(outcome.message).to include("killed by signal 9 during tests")
  end

  it "reports error when re-evaluation raises before tests run" do
    outcome = run_mode("raise_on_eval")
    expect(outcome.status).to eq(:error)
    expect(outcome.message).to include("boom while evaluating", "before tests")
  end

  it "reports error when the child crashes hard before tests run" do
    outcome = run_mode("die_on_eval")
    expect(outcome.status).to eq(:error)
    expect(outcome.message).to include("killed by signal 9 before tests")
  end

  it "reports error when an after_fork hook crashes" do
    hooks.register(:after_fork) { raise "no database" }
    outcome = run_mode("pass")
    expect([outcome.status, outcome.message]).to eq([:error, "RuntimeError: no database (before tests)"])
  end

  it "reports error when an around_mutant hook never runs the tests" do
    hooks.register(:around_mutant) { |_mutation, _run| nil }
    expect(run_mode("pass").status).to eq(:error)
  end

  it "runs around_mutant hooks in the child around the tests" do
    marker = File.join(tmpdir, "around")
    hooks.register(:around_mutant) do |_mutation, run|
      File.write(marker, Process.pid.to_s)
      run.call
    end
    expect(run_mode("pass").status).to eq(:survived)
    expect(File.read(marker).to_i).not_to eq(Process.pid)
  end

  it "times out a hanging child and kills its whole process group" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    outcome = run_mode("hang", timeout: 0.5)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(outcome.status).to eq(:timeout)
    expect(elapsed).to be < 3.0
    grandchild = File.read(File.join(tmpdir, "grandchild.pid")).to_i
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    sleep 0.05 while alive?(grandchild) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    expect(alive?(grandchild)).to be(false)
  end

  it "leaves no child processes behind" do
    %w[pass fail die hang].each { |mode| run_mode(mode, timeout: 0.3) }
    expect { Process.wait(-1, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
  end

  it "keeps the child log only for errors" do
    run_mode("pass")
    run_mode("raise_on_eval")
    expect(Dir.glob(File.join(tmpdir, "child-*.log")).size).to eq(1)
  end
end
