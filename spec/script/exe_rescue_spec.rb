# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

# The executable's own rescue: the CLI's rescue cannot see failures while
# the CLI is being required or constructed, so exe/saboteur reports them.
RSpec.describe "exe/saboteur fallback rescue" do
  def run_exe(fixture, dir:, env: {}, argv: ["run"])
    root = File.expand_path("../..", __dir__)
    rubyopt = [ENV.fetch("RUBYOPT", nil), "-I#{File.join(root, 'lib')}",
               "-r#{File.join(root, 'spec', 'fixtures', 'exe', fixture)}"].compact.join(" ")
    Open3.capture3({ "RUBYOPT" => rubyopt, "BUNDLE_GEMFILE" => File.join(root, "Gemfile") }.merge(env),
                   RbConfig.ruby, File.join(root, "exe", "saboteur"), *argv, chdir: dir)
  end

  it "reports a constructor failure as an internal error with the log path" do
    Dir.mktmpdir do |dir|
      _out, err, status = run_exe("raise_in_constructor.rb", dir:)
      expect(status.exitstatus).to eq(70)
      expect(err).to include("error: the run crashed (StandardError: injected constructor failure)")
      expect(err).to include("the full backtrace is in .saboteur/internal-error.log")
      expect(File.read(File.join(dir, ".saboteur", "internal-error.log"))).to include("injected constructor failure")
    end
  end

  it "prints the backtrace to stderr with --verbose" do
    Dir.mktmpdir do |dir|
      _out, err, status = run_exe("raise_in_constructor.rb", dir:, argv: ["run", "--verbose"])
      expect(status.exitstatus).to eq(70)
      expect(err).to include("raise_in_constructor.rb")
    end
  end

  it "answers an agent with JSON when construction fails" do
    Dir.mktmpdir do |dir|
      out, err, status = run_exe("raise_in_constructor.rb", dir:, argv: ["run", "--agent"])
      expect(status.exitstatus).to eq(70)
      payload = JSON.parse(out)
      expect(payload).to include("status" => "error", "verdict" => "tool_failure", "exitCode" => 70)
      expect(payload["message"]).to include("injected constructor failure")
      expect(err).to include("error: the run crashed")
    end
  end

  it "reports a require-time CLI failure with the log path" do
    Dir.mktmpdir do |dir|
      _out, err, status = run_exe("raise_on_cli_require.rb", dir:)
      expect(status.exitstatus).to eq(70)
      expect(err).to include("error: the run crashed (StandardError: injected require failure)")
      expect(err).to include("the full backtrace is in .saboteur/internal-error.log")
      expect(File.read(File.join(dir, ".saboteur", "internal-error.log"))).to include("injected require failure")
    end
  end

  it "falls back to a normalized one-liner when even the crash reporter cannot load" do
    Dir.mktmpdir do |dir|
      env = { "SABOTEUR_EXE_SPEC_REQUIRE_FAIL" => "saboteur/crash_report",
              "SABOTEUR_EXE_SPEC_MESSAGE" => "first line\nsecond line" }
      _out, err, status = run_exe("raise_on_cli_require.rb", dir:, env:)
      expect(status.exitstatus).to eq(70)
      expect(err).to include("error: the run crashed (StandardError: first line second line)")
      expect(err).not_to include("second line\n")
      expect(err).not_to include("full backtrace")
      expect(File).not_to exist(File.join(dir, ".saboteur", "internal-error.log"))
    end
  end

  it "answers require-time failures with standalone agent JSON for every agent flag spelling" do
    Dir.mktmpdir do |dir|
      [%w[run --agent], %w[run --format agent], %w[run --format=agent]].each do |argv|
        out, _err, status = run_exe("raise_on_cli_require.rb", dir:, argv:)
        expect(status.exitstatus).to eq(70)
        payload = JSON.parse(out)
        expect(payload).to include("status" => "error", "verdict" => "tool_failure", "exitCode" => 70)
        expect(payload["message"]).to include("injected require failure")
      end
    end
  end

  it "collapses a multiline crash message in the one-liner but keeps it in the log" do
    Dir.mktmpdir do |dir|
      _out, err, status = run_exe("raise_in_constructor.rb", dir:, env: { "SABOTEUR_EXE_SPEC_RAISE" => "multiline" })
      expect(status.exitstatus).to eq(70)
      expect(err).to include("error: the run crashed (StandardError: first line second line)")
      expect(File.read(File.join(dir, ".saboteur", "internal-error.log"))).to include("first line\nsecond line")
    end
  end

  it "lets Interrupt keep its own exit" do
    Dir.mktmpdir do |dir|
      _out, err, status = run_exe("raise_in_constructor.rb", dir:, env: { "SABOTEUR_EXE_SPEC_RAISE" => "interrupt" })
      expect(status.exitstatus).not_to eq(70)
      expect(err).not_to include("internal error")
      expect(File).not_to exist(File.join(dir, ".saboteur", "internal-error.log"))
    end
  end

  it "lets SystemExit keep its own status" do
    Dir.mktmpdir do |dir|
      _out, _err, status = run_exe("raise_in_constructor.rb", dir:, env: { "SABOTEUR_EXE_SPEC_RAISE" => "system_exit" })
      expect(status.exitstatus).to eq(4)
    end
  end
end
