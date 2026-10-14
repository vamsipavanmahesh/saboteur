# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::CommandRunner do
  # The suite process is a child subreaper, so a killed grandchild stays a zombie until reaped.
  # ProcessHelpers#alive? treats zombies as dead.
  include ProcessHelpers

  let(:runner) { described_class.new(directory: Dir.pwd, grace: 1) }

  it "reports a clean exit (valid control)" do
    result = runner.run(["ruby", "-e", "puts :ok"])
    expect([result.succeeded?, result.stdout]).to eq([true, "ok\n"])
  end

  it "reports a non-zero exit as not succeeded" do
    result = runner.run(["ruby", "-e", "exit 7"])
    expect([result.ran?, result.succeeded?, result.exit_status]).to eq([true, false, 7])
  end

  it "does not hand arguments to a shell" do
    result = runner.run(["ruby", "-e", "print ARGV.first", "; echo injected"])
    expect(result.stdout).to eq("; echo injected")
  end

  it "reports a missing executable as not run" do
    result = runner.run(["no-such-tool-for-preflight"])
    expect([result.ran?, result.succeeded?,
            result.spawn_error]).to match([false, false, a_string_including("No such file")])
  end

  it "kills the whole process group on timeout, including a grandchild" do
    script = "pid = spawn('sleep 60'); puts pid; $stdout.flush; sleep 60"
    result = runner.run(["ruby", "-e", script], timeout: 1)
    grandchild = result.stdout.to_i
    sleep 0.2
    expect([result.timed_out, result.ran?]).to eq([true, false])
    expect(alive?(grandchild)).to be(false)
  end

  it "escalates to KILL when TERM is ignored" do
    script = "trap('TERM') {}; puts :ready; $stdout.flush; sleep 60"
    result = runner.run(["ruby", "-e", script], timeout: 1)
    expect([result.timed_out, result.signal]).to eq([true, 9])
  end

  it "marks output over the limit as truncated, never as a clean run" do
    limited = described_class.new(directory: Dir.pwd, output_limit: 100)
    result = limited.run(["ruby", "-e", "print 'x' * 1000"])
    expect([result.truncated, result.ran?, result.succeeded?]).to eq([true, false, false])
  end

  it "flags invalid UTF-8 output as unusable instead of repairing it" do
    result = runner.run(["ruby", "-e", "print \"\\xff\\xfe\""])
    expect([result.invalid_encoding, result.ran?, result.succeeded?]).to eq([true, false, false])
  end

  it "does not hang when the leader exits but a grandchild holds the output pipe" do
    script = "spawn('sleep 30', pgroup: false); puts :done"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = runner.run(["ruby", "-e", script])
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(elapsed).to be < 10
    expect([result.stray_processes, result.ran?]).to eq([true, false])
  end

  it "reports a TERM-ignoring child left behind by a leader that exits" do
    script = "pid = spawn('ruby', '-e', \"trap('TERM') {}; sleep 30\"); sleep 0.5; puts pid"
    result = runner.run(["ruby", "-e", script])
    sleep 0.2
    expect(result.stray_processes).to be(true)
    expect(alive?(result.stdout.to_i)).to be(false)
  end

  it "does not hang when a detached grandchild in its own group holds the pipe, and says output is incomplete" do
    script = "pid = spawn('sleep 20', pgroup: true); puts pid; $stdout.flush; sleep 30"
    result = nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = runner.run(["ruby", "-e", script], timeout: 3)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(elapsed).to be < 12
    expect(result.stdout.to_i).to be_positive
    expect([result.truncated, result.ran?]).to eq([true, false])
  ensure
    pid = result&.stdout.to_i
    Process.kill("KILL", pid) if pid&.positive? && alive?(pid)
  end

  it "carries the RSpec report on fd 3 through the shim while suite prints stay on stdout (real run)" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "noisy_spec.rb"), <<~RUBY)
        RSpec.describe("noise") { it("passes") { puts "spec noise"; expect(1).to eq(1) } }
      RUBY
      loud = described_class.new(directory: dir, log_directory: File.join(dir, "logs"), grace: 1)
      loud.log_root = dir
      result = loud.run(["bundle", "exec", "rspec", "noisy_spec.rb", "--require", loud.data_shim_path,
                         "--format", "json"], timeout: 120, data_pipe: true)
      expect([result.ran?, result.problem]).to eq([true, nil])
      expect(result.stdout).to include("spec noise")
      document = Preflight::StrictJson.parse(result.data)
      expect(document.fetch("summary").fetch("example_count")).to eq(1)
    end
  end

  it "refuses a data pipe without a log directory, where no safe shim can be written" do
    expect { runner.data_shim_path }.to raise_error(Preflight::ExecutionGap, /log directory/)
  end

  it "keeps a clean run clean when nothing is left behind (valid control)" do
    expect(runner.run(["ruby", "-e", "puts 1"]).stray_processes).to be(false)
  end

  it "records a signal death as not succeeded" do
    result = runner.run(["ruby", "-e", "Process.kill('KILL', Process.pid)"])
    expect([result.signal, result.succeeded?]).to eq([9, false])
  end

  it "writes logs and records their digests" do
    Dir.mktmpdir do |logs|
      result = described_class.new(directory: Dir.pwd, log_directory: logs).run(["ruby", "-e", "puts 1"])
      expect(File.read(result.stdout_path)).to eq("1\n")
      expect(result.to_h[:stdout_sha256]).to eq(Digest::SHA256.hexdigest("1\n"))
    end
  end

  it "reports a log write failure as not run" do
    result = described_class.new(directory: Dir.pwd,
                                 log_directory: "/proc/preflight-nope").run(["ruby",
                                                                             "-e", "puts 1"])
    expect([result.ran?, result.spawn_error]).to match([false, a_string_including("log write failed")])
  end

  it "rejects a non-array command" do
    expect { runner.run("echo hi") }.to raise_error(ArgumentError)
  end
end
