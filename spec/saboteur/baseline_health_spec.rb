# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/baseline_health"

RSpec.describe Saboteur::BaselineHealth do
  let(:config) { Saboteur::Config.new }
  let(:integration) { instance_double(Saboteur::Integration::Base, all_tests: [Saboteur::Integration::TestCase.new(id: "a", file: "spec/a.rb")]) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }

  def response(passed: true, executed: ["a"], child_failed: false)
    instance_double(Saboteur::Execution::Supervisor::Result, stopped_by: nil,
                                                             payload: JSON.generate(passed: passed, executed: executed),
                                                             child_failed?: child_failed, leftover_pids: [])
  end

  it "requires two green runs with the same executed sequence" do
    allow(supervisor).to receive(:run).and_return(response, response)
    expect(described_class.new(config, integration: integration, supervisor: supervisor).call).to eq(["a"])
    expect(supervisor).to have_received(:run)
      .with(timeout: 300.0, label: "baseline child died during setup/run").twice
  end

  it "rejects a run whose child exited unsuccessfully by itself" do
    allow(supervisor).to receive(:run).and_return(response(child_failed: true))
    expect { described_class.new(config, integration: integration, supervisor: supervisor).call }
      .to raise_error(Saboteur::Error, /exited unsuccessfully/)
  end

  it "accepts a delivered result when only the supervisor's own kill ended the child" do
    allow(supervisor).to receive(:run).and_return(response(child_failed: false), response(child_failed: false))
    expect(described_class.new(config, integration: integration, supervisor: supervisor).call).to eq(["a"])
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

  it "quotes the bounded child log tail when the child dies after the redirect (#289)" do
    broken = Class.new(StandardError) do
      def message
        raise "message broke"
      end
    end
    allow(integration).to receive(:run_all) do
      warn("baseline noise line
" * 500)
      raise broken
    end
    expect { described_class.new(config, integration: integration).call }
      .to raise_error(Saboteur::Error) do |error|
        expect(error.message).to include("baseline child died during setup/run")
        expect(error.message).to include("without a result (exit 1)")
        expect(error.message).to include("message broke")
        expect(error.message).to include("baseline child died during setup/run: RuntimeError")
        expect(error.message.length).to be < 4096
      end
  end

  describe "#log_tail boundaries (#289)" do
    def tail_of(content)
      log = Tempfile.create("saboteur-baseline")
      log.write(content)
      log.flush
      described_class.new(config, integration: integration).send(:log_tail, log)
    ensure
      path = log&.path
      log&.close
      File.unlink(path) if path && File.exist?(path)
    end

    it "returns an empty string for a nil log" do
      expect(described_class.new(config, integration: integration).send(:log_tail, nil)).to eq("")
    end

    it "returns an empty string for an empty log" do
      expect(tail_of("")).to eq("")
    end

    it "reads a small log in full, joined on one line" do
      expect(tail_of("alpha\nbeta\n")).to eq("; child log tail: alpha / beta")
    end

    it "starts a large log at exactly the 2 KB boundary" do
      content = ("A" * 52) + ("B" * 2048)
      expect(tail_of(content)).to eq("; child log tail: #{'B' * 2048}")
    end

    it "bounds the read to 2 KB even if the file grows after the size check (#289)" do
      log = instance_double(File, size: 10, read: "x")
      allow(log).to receive(:seek)
      expect(described_class.new(config, integration: integration).send(:log_tail, log))
        .to eq("; child log tail: x")
      expect(log).to have_received(:read).with(2048)
    end

    it "keeps exactly the last 20 lines" do
      content = (1..25).map { |n| "line#{n}" }.join("\n")
      tail = tail_of(content)
      expect(tail).to start_with("; child log tail: line6 / line7")
      expect(tail).to end_with("line24 / line25")
      expect(tail).not_to include("line5")
    end
  end

  it "keeps the original exit error when the child log cannot be read (#289)" do
    health = described_class.new(config, integration: integration)
    path = nil
    broken = Tempfile.create("saboteur-baseline") do |log|
      path = log.path
      log.write("last words")
      log
    end
    broken.close
    expect(health.send(:log_tail, broken)).to eq("")
  ensure
    File.unlink(path) if path && File.exist?(path)
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
      .to raise_error(Saboteur::Error,
                      /baseline has no tests; check rspec_args and the suite filters, /)
    expect(supervisor).not_to receive(:run)
  end
end

RSpec.describe Saboteur::BaselineHealth, "#failure_detail" do
  let(:config) { Saboteur::Config.new }
  let(:integration) { instance_double(Saboteur::Integration::Base, all_tests: []) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }

  def health_with_example(exception:, description:)
    example = instance_double(RSpec::Core::Example,
                              execution_result: instance_double(RSpec::Core::Example::ExecutionResult,
                                                                exception: exception),
                              id: "./spec/caf\xE9_spec.rb[1:1]".b, full_description: description)
    allow(RSpec).to receive(:world).and_return(instance_double(RSpec::Core::World, all_examples: [example]))
    described_class.new(config, integration: integration, supervisor: supervisor)
  end

  it "sanitizes a locale-tagged message before stripping it" do
    error = instance_double(RuntimeError, message: "boom caf\xE9 here".dup.force_encoding(Encoding::US_ASCII))
    detail = health_with_example(exception: error, description: "a fails").send(:failure_detail)
    expect(detail).to include("boom caf").and be_valid_encoding
  end

  it "sanitizes a UTF-8 description and a raw-byte message before interpolating them" do
    error = instance_double(RuntimeError, message: "boom \xFF path".b)
    detail = health_with_example(exception: error, description: "h\xC3\xA9llo fails".b).send(:failure_detail)
    expect(detail).to include("héllo fails").and be_valid_encoding
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
    failed = exit_status ? !exit_status.success? : false
    result = instance_double(Saboteur::Execution::Supervisor::Result, stopped_by: nil, payload: payload,
                                                                      exit_status: exit_status, child_failed?: failed,
                                                                      leftover_pids: leftover_pids)
    allow(supervisor).to receive(:run).and_return(result)
    described_class.new(Saboteur::Config.new, integration: integration, supervisor: supervisor).call
  end

  it "rejects missing payload" do
    expect { check(payload: "") }.to raise_error(Saboteur::Error, /without a result/)
  end

  it "reports the child's exit status when the payload is empty (#255)" do
    pid = fork { exit! 1 }
    _, status = Process.wait2(pid)
    expect { check(payload: "", exit_status: status) }
      .to raise_error(Saboteur::Error, /without a result \(exit 1\)/)
  end

  it "reports the child's signal when the payload is empty (#255)" do
    pid = fork { Process.kill("KILL", Process.pid) }
    _, status = Process.wait2(pid)
    expect { check(payload: "", exit_status: status) }
      .to raise_error(Saboteur::Error, /without a result \(signal KILL\)/)
  end

  it "rejects malformed and non-object payloads" do
    ["{", "[]", "null"].each do |payload|
      expect { check(payload: payload) }.to raise_error(Saboteur::Error, /invalid result/)
    end
  end

  it "rejects a nonzero child exit even with green evidence" do
    pid = fork { exit! 7 }
    _, status = Process.wait2(pid)
    expect do
      check(payload: JSON.generate(passed: true,
                                   executed: ["a"]), exit_status: status)
    end
      .to raise_error(Saboteur::Error, /exited unsuccessfully/)
  end

  it "rejects leftover processes" do
    expect do
      check(payload: JSON.generate(passed: true,
                                   executed: ["a"]), leftover_pids: [123])
    end
      .to raise_error(Saboteur::Error, /left processes/)
  end
end

RSpec.describe Saboteur::BaselineHealth, "exact messages" do
  let(:integration) do
    instance_double(Saboteur::Integration::Base,
                    all_tests: [Saboteur::Integration::TestCase.new(id: "a", file: "a.rb")])
  end
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }

  def run_with(**result_fields)
    fields = { stopped_by: nil, payload: "", exit_status: nil, child_failed?: false, leftover_pids: [] }
    result = instance_double(Saboteur::Execution::Supervisor::Result, **fields, **result_fields)
    allow(supervisor).to receive(:run).and_return(result)
    described_class.new(Saboteur::Config.new, integration: integration, supervisor: supervisor).call
  end

  def green = JSON.generate(passed: true, executed: ["a"])

  it "says which run left processes running" do
    expect { run_with(payload: green, leftover_pids: [1]) }
      .to raise_error(Saboteur::Error, "baseline run 1 left processes running; fix suite cleanup")
  end

  it "says which run returned an invalid result, for broken JSON and for a non-object" do
    ["{", "[]"].each do |payload|
      expect { run_with(payload: payload) }
        .to raise_error(Saboteur::Error, "baseline run 1 returned an invalid result")
    end
  end

  it "says which run was stopped and why" do
    expect { run_with(stopped_by: :timeout, detail: "deadline") }
      .to raise_error(Saboteur::Error, "baseline run 1 stopped: deadline")
  end

  it "says which run produced no result, without a log tail when there is none" do
    expect { run_with }.to raise_error(
      Saboteur::Error,
      "baseline child died during setup/run: baseline run 1 exited without a result; check suite boot and exits"
    )
  end

  it "says which run exited unsuccessfully" do
    expect { run_with(payload: green, child_failed?: true) }.to raise_error(
      Saboteur::Error, "baseline run 1 exited unsuccessfully; fix suite cleanup and exit handlers"
    )
  end

  it "wraps an unexpected supervision error with its class, message and a hint" do
    allow(supervisor).to receive(:run).and_raise(ArgumentError, "boom")
    expect { described_class.new(Saboteur::Config.new, integration: integration, supervisor: supervisor).call }
      .to raise_error(Saboteur::Error, "baseline check failed: ArgumentError: boom; check suite hooks and setup")
  end

  it "treats anything but the boolean true as a red run" do
    expect { run_with(payload: JSON.generate(passed: "yes", executed: ["a"])) }
      .to raise_error(Saboteur::Error, "baseline run 1 failed: fix the unchanged suite")
  end

  it "names its temporary log" do
    allow(Tempfile).to receive(:create).and_call_original
    run_with(payload: green)
    expect(Tempfile).to have_received(:create).with("saboteur-baseline").twice
  end
end

RSpec.describe Saboteur::BaselineHealth, "baseline supervision wiring" do
  it "constructs configured limits and supervises both numbered passes" do
    config = Saboteur::Config.new({ "max_memory_mb" => 512, "max_processes" => 8, "baseline_timeout" => 42 })
    integration = instance_double(Saboteur::Integration::Base,
                                  all_tests: [Saboteur::Integration::TestCase.new(id: "a", file: "a.rb")])
    supervisor = instance_double(Saboteur::Execution::Supervisor)
    expect(Saboteur::Execution::Supervisor::Limits).to receive(:new).with(max_memory_mb: 512,
                                                                          max_processes: 8).and_call_original
    expect(Saboteur::Execution::Supervisor).to receive(:new).with(limits: instance_of(Saboteur::Execution::Supervisor::Limits)).and_return(supervisor)
    result = instance_double(Saboteur::Execution::Supervisor::Result, stopped_by: nil,
                                                                      payload: JSON.generate(passed: true,
                                                                                             executed: ["a"]),
                                                                      exit_status: nil,
                                                                      child_failed?: false, leftover_pids: [])
    expect(supervisor).to receive(:run)
      .with(timeout: 42.0, label: "baseline child died during setup/run").twice.and_return(result)
    expect(described_class.new(config, integration: integration).call).to eq(["a"])
  end

  it "reports the second run number, accepts successful exits, and rejects wrong executed types" do
    integration = instance_double(Saboteur::Integration::Base,
                                  all_tests: [Saboteur::Integration::TestCase.new(id: "a", file: "a.rb")])
    supervisor = instance_double(Saboteur::Execution::Supervisor)
    pid = fork { exit! 0 }
    _, status = Process.wait2(pid)
    green = instance_double(Saboteur::Execution::Supervisor::Result, stopped_by: nil,
                                                                     payload: JSON.generate(passed: true,
                                                                                            executed: ["a"]),
                                                                     exit_status: status,
                                                                     child_failed?: false, leftover_pids: [])
    red = instance_double(Saboteur::Execution::Supervisor::Result, stopped_by: nil,
                                                                   payload: JSON.generate(passed: true, executed: "a"),
                                                                   exit_status: status,
                                                                   child_failed?: false, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(green, red)
    expect { described_class.new(Saboteur::Config.new, integration: integration, supervisor: supervisor).call }
      .to raise_error(Saboteur::Error, /baseline run 2 did not execute every/)
  end

  it "rejects nonmatching arrays and red runs with complete evidence" do
    health = described_class.new(Saboteur::Config.new, integration: instance_double(Saboteur::Integration::Base))
    expect { health.send(:verify_execution, { "passed" => true, "executed" => ["b"] }, 1, ["a"]) }
      .to raise_error(Saboteur::Error, /did not execute every/)
    expect { health.send(:verify_execution, { "passed" => false, "executed" => ["a"], "error" => "oops" }, 1, ["a"]) }
      .to raise_error(Saboteur::Error, /failed: oops/)
  end

  it "records real supervised child sequence, seed and after-fork hooks without mutation hooks" do
    integration = Object.new
    def integration.all_tests
      [Saboteur::Integration::TestCase.new(id: "a", file: "a.rb")]
    end

    def integration.run_all(sequence) # rubocop:disable Naming/PredicateMethod
      raise "wrong seed" unless rand(1000) == Random.new(42).rand(1000)
      raise "hook missing" unless ENV["BASELINE_SPEC_HOOK"] == "yes"

      sequence.test_started("a", "a.rb")
      sequence.test_finished("a")
      true
    end
    hooks = Saboteur::Hooks.new
    hooks.register(:after_fork) { ENV["BASELINE_SPEC_HOOK"] = "yes" }
    hooks.register(:before_fork) { raise "mutation hook called" }
    hooks.register(:around_mutant) { raise "mutation hook called" }
    config = Saboteur::Config.new({ "seed" => 42 })
    expect(described_class.new(config, integration: integration, hooks: hooks).call).to eq(["a"])
  end

  it "bounds failure descriptions and first nonempty error lines" do
    exception = RuntimeError.new("\nshort message\nother line")
    example = double(id: "spec/a.rb[1:1]", full_description: "x" * 300, execution_result: double(exception: exception))
    allow(RSpec.world).to receive(:all_examples).and_return([example] * 8)
    health = described_class.new(Saboteur::Config.new, integration: instance_double(Saboteur::Integration::Base))
    detail = health.send(:failure_detail)
    expect(detail.split("; ").size).to eq(5)
    expect(detail).to include("spec/a.rb[1:1]: #{'x' * 200}: short message")
    expect(detail).not_to include("other line")
  end

  it "scrubs raw bytes from failure details so the JSON payload stays valid UTF-8" do
    exception = RuntimeError.new("invalid path raw-\xFF.rb".b)
    example = double(id: "spec/a.rb[1:1]", full_description: "raw bytes",
                     execution_result: double(exception: exception))
    allow(RSpec.world).to receive(:all_examples).and_return([example])
    health = described_class.new(Saboteur::Config.new, integration: instance_double(Saboteur::Integration::Base))
    detail = health.send(:failure_detail)
    expect(detail.encoding).to eq(Encoding::UTF_8)
    expect(detail).to be_valid_encoding
    expect(JSON.generate(error: detail)).to include("raw-")
  end
end

RSpec.describe Saboteur::BaselineHealth, "child record in process" do
  let(:config) { Saboteur::Config.new({ "seed" => 42 }) }
  let(:integration) { instance_double(Saboteur::Integration::Base) }
  let(:hooks) { instance_double(Saboteur::Hooks) }
  let(:health) { described_class.new(config, integration: integration, hooks: hooks) }
  let(:writer) { StringIO.new }

  before do
    allow($stdout).to receive(:reopen)
    allow($stderr).to receive(:reopen)
    allow(Kernel).to receive(:srand)
    allow(RSpec.configuration).to receive(:order=)
    allow(hooks).to receive(:run)
  end

  it "records sequence and failed example details, reseeds and closes the writer" do
    expect($stdout).to receive(:reopen).with("/tmp/baseline-log", "w")
    expect($stderr).to receive(:reopen).with($stdout)
    expect(hooks).to receive(:run).with(:after_fork)
    expect(Kernel).to receive(:srand).with(42)
    expect(RSpec.configuration).to receive(:order=).with("rand:42")
    allow(integration).to receive(:run_all) do |sequence|
      expect(sequence.executed).to eq([])
      sequence.test_started("a", "a.rb")
      sequence.test_finished("a")
      sequence.test_finished("b")
      false
    end
    allow(health).to receive(:failure_detail).and_return("failure identity")
    health.send(:record, writer, "/tmp/baseline-log")
    expect(JSON.parse(writer.string)).to eq("passed" => false, "executed" => %w[a b], "error" => "failure identity")
    expect(writer).to be_closed
  end

  it "captures child exceptions and still closes the pipe" do
    allow(integration).to receive(:run_all).and_raise(SyntaxError, "bad syntax")
    health.send(:record, writer, "/tmp/baseline-log")
    expect(JSON.parse(writer.string)).to eq("passed" => false, "error" => "SyntaxError: bad syntax")
    expect(writer).to be_closed
  end

  it "returns nil without RSpec and skips examples without exceptions" do
    allow(RSpec.world).to receive(:all_examples).and_return([double(execution_result: double(exception: nil))])
    expect(health.send(:failure_detail)).to eq("")
    checker = health
    rspec = Object.send(:remove_const, :RSpec)
    begin
      detail = checker.send(:failure_detail)
    ensure
      Object.const_set(:RSpec, rspec)
    end
    expect(detail).to be_nil
  end

  it "uses exactly the first 200 characters of messages and descriptions" do
    example = double(id: "test", full_description: "A#{'b' * 299}",
                     execution_result: double(exception: RuntimeError.new("M#{'n' * 299}")))
    allow(RSpec.world).to receive(:all_examples).and_return([example])
    expect(health.send(:failure_detail)).to eq("test: A#{'b' * 199}: M#{'n' * 199}")
  end

  it "preserves known errors and wraps unexpected supervision errors" do
    supervisor = instance_double(Saboteur::Execution::Supervisor)
    health = described_class.new(config, integration: integration, supervisor: supervisor)
    error = Saboteur::Error.new("known")
    allow(supervisor).to receive(:run).and_raise(error)
    expect { health.send(:check_run, 1, ["a"]) }.to(raise_error { |raised| expect(raised).to equal(error) })
    allow(supervisor).to receive(:run).and_raise(RuntimeError, "unexpected")
    expect do
      health.send(:check_run, 1, ["a"])
    end.to raise_error(Saboteur::Error, /baseline check failed: RuntimeError: unexpected/)
    expect { health.send(:verify_execution, { "passed" => false }, 1, ["a"]) }
      .to raise_error(Saboteur::Error, /failed: fix the unchanged suite/)
  end
end

RSpec.describe Saboteur::BaselineHealth, "record without RSpec" do
  it "records an adapter run even when RSpec is not loaded" do
    integration = Object.new
    def integration.run_all(sequence) # rubocop:disable Naming/PredicateMethod
      sequence.test_finished("a")
      true
    end
    health = described_class.new(Saboteur::Config.new, integration: integration)
    writer = StringIO.new
    stdout = $stdout.dup
    stderr = $stderr.dup
    rspec = Object.send(:remove_const, :RSpec)
    begin
      Tempfile.create("baseline-spec") { |log| health.send(:record, writer, log.path) }
    ensure
      Object.const_set(:RSpec, rspec)
      $stdout.reopen(stdout)
      $stderr.reopen(stderr)
      stdout.close
      stderr.close
    end
    expect(JSON.parse(writer.string)).to eq("passed" => true, "executed" => ["a"], "error" => nil)
    expect(writer).to be_closed
  end
end
