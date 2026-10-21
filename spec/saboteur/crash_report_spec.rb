# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"
require "timeout"
require "tmpdir"

RSpec.describe Saboteur::CrashReport do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:error) do
    RuntimeError.new("boom").tap do |e|
      e.set_backtrace(["app/models/thing.rb:10:in `explode'", "app/models/thing.rb:20:in `run'"])
    end
  end

  def report(error, log_path: nil, verbose: false, agent: false, color: :auto)
    described_class.call(error, verbose:, agent:, err:, out:, log_path:, color:)
  end

  it "returns the crash exit code" do
    expect(report(error)).to eq(70)
  end

  it "prints the crash verdict line, red only when colour is forced on" do
    report(error)
    expect(err.string).to include("exit 70 - internal crash (a saboteur bug, never your code)")
    expect(err.string).not_to include("\e[")

    err.truncate(0)
    err.rewind
    report(error, color: :always)
    expect(err.string).to include("\e[31;1mexit 70 - internal crash (a saboteur bug, never your code)\e[0m")

    err.truncate(0)
    err.rewind
    report(error, color: :never)
    expect(err.string).not_to include("\e[")
  end

  it "prints the one-line diagnostic with the report URL" do
    report(error)
    expect(err.string).to include("error: the run crashed (RuntimeError: boom)")
    expect(err.string).to include("please report it: https://github.com/vamsipavanmahesh/saboteur/issues")
  end

  it "writes the backtrace to the log file and names the path" do
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      report(error, log_path:)
      expect(err.string).to include("the full backtrace is in #{log_path}")
      expect(File.read(log_path)).to eq(
        "RuntimeError: boom\napp/models/thing.rb:10:in `explode'\napp/models/thing.rb:20:in `run'\n"
      )
    end
  end

  it "never redirects the primary log write through a symlink (#296)" do
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      FileUtils.mkdir_p(File.dirname(log_path))
      File.symlink(File.join(root, "target"), log_path)
      fallback = described_class.tmp_log_path
      FileUtils.rm_f(fallback)
      report(error, log_path:)
      expect(err.string).to include("the full backtrace is in #{fallback}")
      expect(File).to be_symlink(log_path)
      expect(File).not_to exist(File.join(root, "target"))
    ensure
      FileUtils.rm_f(fallback)
    end
  end

  it "falls back promptly when the primary log path is a no-reader FIFO (#296)" do
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      FileUtils.mkdir_p(File.dirname(log_path))
      File.mkfifo(log_path)
      fallback = described_class.tmp_log_path
      FileUtils.rm_f(fallback)
      Timeout.timeout(10) { report(error, log_path:) }
      expect(err.string).to include("the full backtrace is in #{fallback}")
      expect(File).to be_pipe(log_path)
    ensure
      FileUtils.rm_f(fallback)
    end
  end

  it "creates the primary log with mode 0600 from the first open, not only after the chmod (#296)" do
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      create_modes = {}
      allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
        create_modes[args[0]] = args[2] if args.length >= 3
        original.call(*args, &block)
      end
      report(error, log_path:)
      expect(create_modes[log_path]).to eq(0o600)
    end
  end

  it "keeps the log private even when it pre-exists with wider permissions (#296)" do
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      FileUtils.mkdir_p(File.dirname(log_path))
      File.write(log_path, "old")
      FileUtils.chmod(0o644, log_path)
      report(error, log_path:)
      expect(File.read(log_path)).to include("RuntimeError: boom")
      expect(File.stat(log_path).mode & 0o777).to eq(0o600)
    end
  end

  it "creates the log directory when it is missing" do
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      report(error, log_path:)
      expect(File).to exist(log_path)
    end
  end

  it "writes the log to the pid-keyed temp fallback when the cache dir cannot hold it (#296)" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".saboteur"), "a file, not a directory")
      fallback = described_class.tmp_log_path
      FileUtils.rm_f(fallback)
      report(error, log_path: File.join(root, ".saboteur", "internal-error.log"))
      expect(err.string).to include("the full backtrace is in #{fallback}")
      expect(File.read(fallback)).to eq(
        "RuntimeError: boom\napp/models/thing.rb:10:in `explode'\napp/models/thing.rb:20:in `run'\n"
      )
      FileUtils.rm_f(fallback)
    end
  end

  it "computes the temp fallback lazily, only after the primary write fails (#296)" do
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      allow(described_class).to receive(:tmp_log_path).and_raise(ArgumentError, "no tmpdir")
      report(error, log_path:)
      expect(err.string).to include("the full backtrace is in #{log_path}")
      expect(File.read(log_path)).to include("RuntimeError: boom")
    end
  end

  it "skips the primary log write where safe log IO is unavailable, keeping the temp fallback (#296)" do
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      fallback = described_class.tmp_log_path
      FileUtils.rm_f(fallback)
      allow(described_class).to receive(:safe_log_io?).and_return(false)
      report(error, log_path:)
      expect(File).not_to exist(log_path)
      expect(err.string).to include("the full backtrace is in #{fallback}")
      expect(File.read(fallback)).to include("RuntimeError: boom")
    ensure
      FileUtils.rm_f(fallback)
    end
  end

  it "opens logs with O_NOFOLLOW and O_NONBLOCK where the platform defines them (#296)" do
    expect(described_class.nofollow_flag).to eq(File::NOFOLLOW)
    expect(described_class.nonblock_flag).to eq(File::NONBLOCK)
  end

  it "omits each open flag where the platform lacks it (#296)" do
    allow(File).to receive(:const_defined?).and_call_original
    allow(File).to receive(:const_defined?).with(:NOFOLLOW).and_return(false)
    allow(File).to receive(:const_defined?).with(:NONBLOCK).and_return(false)
    expect(described_class.nofollow_flag).to eq(0)
    expect(described_class.nonblock_flag).to eq(0)
  end

  it "treats log IO as unsafe without O_NOFOLLOW (#296)" do
    allow(File).to receive(:const_defined?).and_call_original
    allow(File).to receive(:const_defined?).with(:NOFOLLOW).and_return(false)
    expect(described_class.safe_log_io?).to be(false)
  end

  it "treats log IO as unsafe without O_NONBLOCK (#296)" do
    allow(File).to receive(:const_defined?).and_call_original
    allow(File).to receive(:const_defined?).with(:NONBLOCK).and_return(false)
    expect(described_class.safe_log_io?).to be(false)
  end

  it "creates the temp fallback privately, pinned to 0600 (#296)" do
    fallback = described_class.tmp_log_path
    FileUtils.rm_f(fallback)
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".saboteur"), "a file, not a directory")
      report(error, log_path: File.join(root, ".saboteur", "internal-error.log"))
      expect(err.string).to include("the full backtrace is in #{fallback}")
      expect(File.stat(fallback).mode & 0o777).to eq(0o600)
    end
  ensure
    FileUtils.rm_f(fallback)
  end

  it "neither follows nor overwrites a pre-existing symlink at the temp fallback path (#296)" do
    fallback = described_class.tmp_log_path
    FileUtils.rm_f(fallback)
    Dir.mktmpdir do |root|
      target = File.join(root, "target")
      File.symlink(target, fallback)
      File.write(File.join(root, ".saboteur"), "a file, not a directory")
      report(error, log_path: File.join(root, ".saboteur", "internal-error.log"))
      expect(err.string).not_to include("full backtrace")
      expect(File).to be_symlink(fallback)
      expect(File).not_to exist(target)
    end
  ensure
    FileUtils.rm_f(fallback)
  end

  it "does not overwrite a pre-existing file at the temp fallback path (#296)" do
    fallback = described_class.tmp_log_path
    File.write(fallback, "not ours")
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".saboteur"), "a file, not a directory")
      report(error, log_path: File.join(root, ".saboteur", "internal-error.log"))
      expect(err.string).not_to include("full backtrace")
      expect(File.read(fallback)).to eq("not ours")
    end
  ensure
    FileUtils.rm_f(fallback)
  end

  it "falls back to the bare one-liner when even the temp fallback cannot be written" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".saboteur"), "a file, not a directory")
      blocked = File.join(root, ".saboteur", "internal-error.log")
      allow(described_class).to receive(:tmp_log_path).and_return(blocked)
      report(error, log_path: blocked)
      expect(err.string).to include("error: the run crashed (RuntimeError: boom)")
      expect(err.string).not_to include("full backtrace")
    end
  end

  it "omits the log path when none is available" do
    report(error)
    expect(err.string).not_to include("full backtrace")
  end

  it "names the temp fallback with the pid and the standard log name" do
    expect(described_class.tmp_log_path).to eq(File.join(Dir.tmpdir, "saboteur-#{Process.pid}-internal-error.log"))
  end

  it "prints the backtrace to stderr with verbose" do
    report(error, verbose: true)
    expect(err.string).to include("app/models/thing.rb:10:in `explode'")
  end

  it "keeps the backtrace off stderr without verbose" do
    report(error)
    expect(err.string).not_to include("app/models/thing.rb:10")
  end

  it "renders the failure as agent JSON to stdout in agent mode" do
    expect(Saboteur::Reporter::Agent).to receive(:failure).and_call_original
    report(error, agent: true)
    expect(out.string).to include("internal error (RuntimeError: boom)")
    expect(err.string).not_to include('"verdict"')
  end

  it "emits a standalone agent failure JSON when the agent reporter never loaded" do
    hide_const("Saboteur::Reporter::Agent")
    expect(report(error, agent: true)).to eq(70)
    payload = JSON.parse(out.string)
    expect(payload).to include(
      "version" => 1, "status" => "error", "verdict" => "tool_failure",
      "exitCode" => 70, "next" => { "help" => "saboteur help run" }
    )
    expect(payload["message"]).to include("internal error (RuntimeError: boom)")
    expect(err.string).to include("error: the run crashed (RuntimeError: boom)")
  end

  it "keeps agent mode silent on stdout when not an agent" do
    report(error)
    expect(out.string).to eq("")
  end

  it "scrubs locale-invalid bytes in the log file" do
    dirty = RuntimeError.new("broken \xFF byte".dup.force_encoding(Encoding::UTF_8))
    dirty.set_backtrace(["x.rb:1"])
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      report(dirty, log_path:)
      expect(File.read(log_path)).to include("broken ? byte")
    end
  end

  it "collapses a multiline message in the one-liner but not in the log" do
    multi = RuntimeError.new("first line\nsecond line")
    multi.set_backtrace(["x.rb:1"])
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      report(multi, log_path:)
      expect(err.string).to include("error: the run crashed (RuntimeError: first line second line)")
      expect(File.read(log_path)).to include("first line\nsecond line")
    end
  end
end
