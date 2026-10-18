# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::RunBudgetOptions do
  def parse(value)
    Object.new.extend(described_class).send(:parse_duration, value)
  end

  it "parses suffixes and bare seconds, ignoring surrounding whitespace (#296)" do
    expect(parse(" 10m ")).to eq(600.0)
    expect(parse("90")).to eq(90.0)
    expect(parse("1.5h")).to eq(5400.0)
  end

  it "documents that the budget clock starts at engine entry (#637)" do
    require "optparse"
    parser = OptionParser.new
    Object.new.extend(described_class).send(:add_run_budget_options, parser)
    expect(parser.to_s).to include("the clock starts at engine entry")
  end

  it "rejects junk with the full hint (#296)" do
    expect { parse("soon") }
      .to raise_error(Saboteur::ConfigError,
                      'invalid --max-duration "soon": use seconds or an s/m/h suffix, e.g. 10m')
  end
end
