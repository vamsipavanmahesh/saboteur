# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"
require "tmpdir"

RSpec.describe Saboteur::CrashReport do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:error) do
    RuntimeError.new("boom").tap do |e|
      e.set_backtrace(["app/models/thing.rb:10:in `explode'", "app/models/thing.rb:20:in `run'"])
    end
  end

  def report(error, log_path: nil, verbose: false, agent: false)
    described_class.call(error, verbose:, agent:, err:, out:, log_path:)
  end

  it "returns the tool-failure exit code" do
    expect(report(error)).to eq(3)
  end

  it "prints the one-line diagnostic with the report URL" do
    report(error)
    expect(err.string).to include("saboteur: internal error (RuntimeError: boom)")
    expect(err.string).to include("please report it: https://github.com/vamsipavanmahesh/saboteur/issues")
  end

  it "writes the backtrace to the log file and names the path" do
    Dir.mktmpdir do |root|
      log_path = File.join(root, ".saboteur", "internal-error.log")
      report(error, log_path:)
      expect(err.string).to include("full backtrace: #{log_path}")
      expect(File.read(log_path)).to eq(
        "RuntimeError: boom\napp/models/thing.rb:10:in `explode'\napp/models/thing.rb:20:in `run'\n"
      )
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
      expect(err.string).to include("full backtrace: #{fallback}")
      expect(File.read(fallback)).to include("RuntimeError: boom")
      FileUtils.rm_f(fallback)
    end
  end

  it "falls back to the bare one-liner when even the temp fallback cannot be written" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".saboteur"), "a file, not a directory")
      blocked = File.join(root, ".saboteur", "internal-error.log")
      allow(described_class).to receive(:tmp_log_path).and_return(blocked)
      report(error, log_path: blocked)
      expect(err.string).to include("internal error (RuntimeError: boom)")
      expect(err.string).not_to include("full backtrace")
    end
  end

  it "uses the temp fallback when no log path is configured" do
    fallback = described_class.tmp_log_path
    FileUtils.rm_f(fallback)
    report(error)
    expect(err.string).to include("full backtrace: #{fallback}")
    FileUtils.rm_f(fallback)
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
    expect(report(error, agent: true)).to eq(3)
    payload = JSON.parse(out.string)
    expect(payload).to include(
      "version" => 1, "status" => "error", "verdict" => "tool_failure",
      "exitCode" => 3, "next" => { "help" => "saboteur help run" }
    )
    expect(payload["message"]).to include("internal error (RuntimeError: boom)")
    expect(err.string).to include("internal error (RuntimeError: boom)")
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
      expect(err.string).to include("internal error (RuntimeError: first line second line)")
      expect(File.read(log_path)).to include("first line\nsecond line")
    end
  end
end
