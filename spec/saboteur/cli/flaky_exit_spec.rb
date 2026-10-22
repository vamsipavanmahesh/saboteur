# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::CLI::FlakyExit do
  let(:harness) do
    Class.new do
      include Saboteur::CLI::FlakyExit

      attr_reader :err

      def initialize = @err = StringIO.new

      def disagreement?(report) = flaky_disagreement?(report)
    end.new
  end

  def report_of_flags(*flags)
    results = flags.each_with_index.map { |flag, i| instance_double(Saboteur::MutantResult, flaky?: flag, digest: "d#{i}") }
    instance_double(Saboteur::Report, results: results)
  end

  it "is false and silent when no result is a flaky disagreement" do
    expect(harness.disagreement?(report_of_flags(false, false))).to be(false)
    expect(harness.disagreement?(report_of_flags)).to be(false)
    expect(harness.err.string).to eq("")
  end

  it "is true, naming only the flaky digests, when one flipped" do
    expect(harness.disagreement?(report_of_flags(false, true))).to be(true)
    expect(harness.err.string).to include("1 mutant changed verdict", "(d1)")
    expect(harness.err.string).not_to include("d0")
  end
end
