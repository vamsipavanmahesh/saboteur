# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"
require "stringio"

# Pins the exact limit error text and option help of Gates, and two
# ExitStatus paths the run specs only reach indirectly.
RSpec.describe Saboteur::Gates do
  it "names the setting and quotes the bad value in the malformed-limit error" do
    expect { described_class.limit("many", "max_errors") }.to raise_error(
      Saboteur::ConfigError, 'max_errors must be a count (3) or a percentage (5%), got "many"'
    )
  end

  it "words each flag's help with its status, in the setting order" do
    parser = OptionParser.new
    described_class.define_options(parser) { |_key, _value| nil }
    lines = parser.to_s.lines.map { |line| line.strip.squeeze(" ") }
    expect(lines.last(2)).to eq(["--max-timeouts N Exit 1 when more than N mutants end as timeout (N or N%)",
                                 "--max-errors N Exit 1 when more than N mutants end as error (N or N%)"])
  end

  it "keeps a separate normalized limit for each setting" do
    gates = described_class.new("max_timeouts" => "3", "max_errors" => "5%")
    expect(gates.instance_variable_get(:@limits)).to eq("max_timeouts" => 3, "max_errors" => "5%")
  end
end

RSpec.describe Saboteur::CLI::ExitStatus do
  let(:harness) do
    Class.new do
      include Saboteur::CLI::ExitStatus
      include Saboteur::CLI::FailureOutput

      attr_reader :config

      def initialize(config)
        @config = config
      end

      def log_path = crash_log_path

      def cause(report, code) = exit_cause(report, code)
    end
  end

  it "records budgetExhausted for the budget exit code, before looking at the report" do
    expect(harness.new(nil).cause(instance_double(Saboteur::Report), Saboteur::CLI::EXIT_BUDGET))
      .to eq("budgetExhausted")
  end

  it "puts the crash log in the cache directory" do
    config = instance_double(Saboteur::Config)
    allow(config).to receive(:path).with("cache_dir").and_return("/cache")
    expect(harness.new(config).log_path).to eq(File.join("/cache", Saboteur::CrashReport::LOG_NAME))
  end

  it "has no crash log when the cache directory is unset or the config is broken" do
    config = instance_double(Saboteur::Config)
    allow(config).to receive(:path).with("cache_dir").and_return(nil)
    expect(harness.new(config).log_path).to be_nil
    allow(config).to receive(:path).with("cache_dir").and_raise(Saboteur::ConfigError, "broken")
    expect(harness.new(config).log_path).to be_nil
  end
end
