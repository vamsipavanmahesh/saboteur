# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::MutationSource::OperatorRegistry do
  let(:all_names) { described_class::DESCRIPTIONS.keys }

  it "selects every operator for no names, and honors exclusions over selections" do
    expect(described_class.select([], [])).to eq(all_names)
    expect(described_class.select(%w[range comparison], %w[range])).to eq(%w[comparison])
    expect(described_class.select([], %w[range])).to eq(all_names - %w[range])
  end

  it "keeps the order given and drops repeats, and expands the all tier" do
    expect(described_class.resolve(%w[range comparison range])).to eq(%w[range comparison])
    expect(described_class.resolve(%w[all])).to eq(all_names)
  end

  it "reports the policy with its version" do
    expect(described_class.policy(%w[range], %w[comparison]))
      .to eq("version" => 3, "selected" => %w[range], "excluded" => %w[comparison], "effective" => %w[range])
  end

  it "refuses removed tiers and unknown names with a hint" do
    expect { described_class.resolve(%w[core]) }
      .to raise_error(Saboteur::ConfigError, /operator tiers core were removed.*exclude range,operator_assignment/)
    expect { described_class.resolve(%w[comparisn]) }
      .to raise_error(Saboteur::ConfigError, /unknown operators: comparisn\. Valid names: .*Did you mean comparison\?/)
    expect(described_class.suggestion("zzzzzz")).to eq("")
  end

  it "suggests only for the first unknown name and points to --list-operators" do
    expect { described_class.resolve(%w[zzzzzz comparisn]) }
      .to raise_error(Saboteur::ConfigError, /unknown operators: zzzzzz, comparisn\. Valid names: .*all\.  See --list/)
    expect { described_class.resolve(%w[comparisn zzzzzz]) }
      .to raise_error(Saboteur::ConfigError, /\. Did you mean comparison\? See --list-operators\.\z/)
  end

  it "describes element_removal as working on any array literal" do
    expect(described_class::DESCRIPTIONS.fetch("element_removal")).to eq("Remove an element of an array literal")
  end

  it "lists each operator as on or off with its description and example" do
    out = StringIO.new
    described_class.list(out, names: %w[range], excluded: [])
    expect(out.string).to include("range  on  #{described_class::DESCRIPTIONS.fetch('range')}  1..3 -> 1...3\n")
    expect(out.string).to match(/^comparison  off  /)
  end
end
