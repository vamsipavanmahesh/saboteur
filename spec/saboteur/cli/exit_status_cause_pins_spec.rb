# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::CLI::ExitStatus do
  let(:harness) do
    Class.new do
      include Saboteur::CLI::ExitStatus
      include Saboteur::CLI::FailureOutput

      attr_reader :config

      def initialize(config)
        @config = config
        @err = StringIO.new
        @out = StringIO.new
      end

      def cause(report, code) = exit_cause(report, code)

      def log_path = crash_log_path
    end.new(config)
  end

  describe "#exit_cause for the budget exit code" do
    let(:config) { {} }

    it "names budgetExhausted" do
      report = instance_double(Saboteur::Report, majority_errored?: false)

      expect(harness.cause(report, Saboteur::CLI::EXIT_BUDGET)).to eq("budgetExhausted")
    end
  end

  describe "#exit_cause for the exits no report can describe" do
    let(:config) { {} }

    it "names baselineRed and crash" do
      report = instance_double(Saboteur::Report)

      expect(harness.cause(report, Saboteur::CLI::EXIT_BASELINE_RED)).to eq("baselineRed")
      expect(harness.cause(report, Saboteur::CLI::EXIT_CRASH)).to eq("crash")
    end

    it "round-trips each machine cause to the human verdict line" do
      expect(Saboteur::CLI::ErrorCause.verdict_line(5)).to eq("exit 5 - baseline suite red: fix your tests first")
      expect(Saboteur::CLI::ErrorCause.verdict_line(70))
        .to eq("exit 70 - internal crash (a saboteur bug, never your code)")
      expect(Saboteur::CLI::ErrorCause::CAUSE_LINES.keys)
        .to eq([Saboteur::CLI::EXIT_BASELINE_RED, Saboteur::CLI::EXIT_CRASH])
      expect(Saboteur::CLI::ErrorCause.cause(5)).to eq("baselineRed")
      expect(Saboteur::CLI::ErrorCause.cause(70)).to eq("crash")
      expect(Saboteur::CrashReport::VERDICT_LINE).to eq(Saboteur::CLI::ErrorCause.verdict_line(70))
    end
  end

  describe "#crash_log_path" do
    context "when reading the cache directory raises" do
      let(:config) do
        instance_double(Saboteur::Config).tap { |c| allow(c).to receive(:path).and_raise(Saboteur::ConfigError, "bad") }
      end

      it "returns nil instead of swallowing the crash report" do
        expect(harness.log_path).to be_nil
      end
    end

    context "when the cache directory is set" do
      let(:config) { instance_double(Saboteur::Config, path: "/tmp/cache-dir") }

      it "puts the crash log under it" do
        expect(harness.log_path).to eq(File.join("/tmp/cache-dir", Saboteur::CrashReport::LOG_NAME))
      end
    end
  end
end
