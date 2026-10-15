# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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
      expect(status.exitstatus).to eq(3)
      expect(err).to include("saboteur: internal error (StandardError: injected constructor failure)")
      expect(err).to include("full backtrace: .saboteur/internal-error.log")
      expect(File.read(File.join(dir, ".saboteur", "internal-error.log"))).to include("injected constructor failure")
    end
  end

  it "prints the backtrace to stderr with --verbose" do
    Dir.mktmpdir do |dir|
      _out, err, status = run_exe("raise_in_constructor.rb", dir:, argv: ["run", "--verbose"])
      expect(status.exitstatus).to eq(3)
      expect(err).to include("raise_in_constructor.rb")
    end
  end

  it "answers an agent with JSON when construction fails" do
    Dir.mktmpdir do |dir|
      out, err, status = run_exe("raise_in_constructor.rb", dir:, argv: ["run", "--agent"])
      expect(status.exitstatus).to eq(3)
      expect(out).to include("injected constructor failure")
      expect(err).to include("internal error")
    end
  end

  it "still exits 3 with a bare one-liner when the CLI itself cannot be required" do
    Dir.mktmpdir do |dir|
      _out, err, status = run_exe("raise_on_cli_require.rb", dir:)
      expect(status.exitstatus).to eq(3)
      expect(err).to include("saboteur: internal error (StandardError: injected require failure)")
      expect(err).not_to include("full backtrace")
      expect(File).not_to exist(File.join(dir, ".saboteur", "internal-error.log"))
    end
  end

  it "lets Interrupt keep its own exit" do
    Dir.mktmpdir do |dir|
      _out, err, status = run_exe("raise_in_constructor.rb", dir:, env: { "SABOTEUR_EXE_SPEC_RAISE" => "interrupt" })
      expect(status.exitstatus).not_to eq(3)
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
