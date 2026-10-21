# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rspec/core"
require "rspec/core/sandbox"
require "stringio"
require "tmpdir"

# execute drives real RSpec reporters and groups, so each scenario runs real
# examples from a throwaway spec directory inside an RSpec sandbox.
RSpec.describe Saboteur::Integration::RSpec, "#execute with real examples" do
  # RSpec's own sandbox gives the scenario a fresh world and configuration,
  # so the examples written here never join the running suite.
  def run_scenario(specs, log_phase: false, files: nil)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec"))
      specs.each { |name, body| File.write(File.join(dir, "spec", name), body) }
      Dir.chdir(File.realpath(dir)) { sandboxed_execute(log_phase, files) }
    end
  end

  def relative(ids) = ids.map { |id| id.sub(%r{\A.*/spec/}, "./spec/") }

  def passing
    { "a_spec.rb" => "RSpec.describe('a') { it('a1') { }; it('a2') { } }\n" }
  end

  def failing
    { "b_spec.rb" => "RSpec.describe('b') { it('b1') { expect(1).to eq(2) } }\n" }
  end

  def sandboxed_execute(log_phase, files)
    captured = StringIO.new
    result = nil
    RSpec::Core::Sandbox.sandboxed do |config|
      config.output_stream = captured
      config.error_stream = captured
      integration = described_class.new(Saboteur::Config.new({ "tests" => ["spec"] }, root: Dir.pwd))
      original = [$stdout, $stderr]
      $stdout = $stderr = captured
      begin
        integration.setup
        listener = described_class::Listener.new
        ok = integration.send(:execute, listener, log_phase: log_phase, files: files)
        messages = listener.failure_messages.transform_keys { |id| relative([id]).first }
        result = { "ok" => ok, "executed" => relative(listener.executed), "failed" => relative(listener.failed),
                   "runtime" => listener.runtime, "failure_messages" => messages }
      ensure
        $stdout, $stderr = original
      end
    end
    [result, captured.string]
  end

  it "runs a clean suite and reports success, the executed ids and the runtime" do
    result, logged = run_scenario(passing)
    expect(logged).not_to include("examples finished")
    expect(result["ok"]).to be(true)
    expect(result["executed"]).to contain_exactly("./spec/a_spec.rb[1:1]", "./spec/a_spec.rb[1:2]")
    expect(result["failed"]).to eq([])
    expect(result["runtime"]).to be >= 0
  end

  it "reports a failing group with the failing id and a nonzero-looking failure" do
    result, = run_scenario(passing.merge(failing))
    expect(result["ok"]).to be(false)
    expect(result["failed"]).to contain_exactly("./spec/b_spec.rb[1:1]")
    expect(result["executed"]).to contain_exactly("./spec/a_spec.rb[1:1]", "./spec/a_spec.rb[1:2]",
                                                  "./spec/b_spec.rb[1:1]")
    expect(result["failure_messages"]["./spec/b_spec.rb[1:1]"]).to include("expected: 2")
  end

  it "fails the run when a suite hook raises outside any example" do
    hook = "RSpec.configure { |c| c.before(:suite) { raise 'boom in suite hook' } }\n" \
           "RSpec.describe('s') { it('x') { } }\n"
    suite = { "s_spec.rb" => hook }
    result, = run_scenario(suite)
    expect(result["ok"]).to be(false)
  end

  it "runs only the groups the listed files define" do
    result, = run_scenario(passing.merge(failing), files: ["spec/a_spec.rb"])
    expect(result["ok"]).to be(true)
    expect(result["executed"]).to contain_exactly("./spec/a_spec.rb[1:1]", "./spec/a_spec.rb[1:2]")
  end

  it "writes progress and totals to the phase log" do
    _, logged = run_scenario(passing, log_phase: true)
    expect(logged).to include("2/2 examples finished")
    expect(logged).to include("2 examples, 0 failures")
  end

  it "counts only the examples of the listed files for the progress total" do
    _, logged = run_scenario(passing.merge(failing), log_phase: true, files: ["spec/a_spec.rb"])
    expect(logged).to include("2/2 examples finished")
    expect(logged).not_to include("3/3")
  end
end
