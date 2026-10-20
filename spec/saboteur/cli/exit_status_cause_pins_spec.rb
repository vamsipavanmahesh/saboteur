# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::CLI::ExitStatus do
  let(:harness) do
    Class.new do
      include Saboteur::CLI::ExitStatus

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
