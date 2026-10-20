# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"

RSpec.describe Saboteur::CLI::RunBudgetOptions, "duration pins" do
  def parse(value)
    Object.new.extend(described_class).send(:parse_duration, value)
  end

  it "rejects values with extra text on either side, or without digits" do
    ["x10m", "10mx", "m", ".5", "1.", "10m\n20m", "5 m"].each do |value|
      expect { parse(value) }.to raise_error(Saboteur::ConfigError, /invalid --max-duration/), value.inspect
    end
  end

  it "accepts fractions and every unit" do
    expect(parse("0.5")).to eql(0.5)
    expect(parse("2s")).to eql(2.0)
    expect(parse("2h")).to eql(7200.0)
  end

  it "keeps the full --max-duration help text, including the coverage map note" do
    parser = OptionParser.new
    Object.new.extend(described_class).send(:add_run_budget_options, parser)
    expect(parser.to_s.gsub(/\s+/, " ")).to include(
      "the clock starts at engine entry, so boot, baselines and the coverage map spend it too"
    )
  end
end
