# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Text do
  it "rejects invalid UTF-8 with a parse error naming the problem" do
    expect { described_class.utf8_strict("\xFF".b) }.to raise_error(JSON::ParserError, "invalid UTF-8")
  end

  it "returns valid input retagged as UTF-8" do
    expect(described_class.utf8_strict("ok".b)).to eq("ok")
  end

  describe ".name_list" do
    it "names every item up to the limit, with no tail" do
      expect(described_class.name_list(%w[a b c])).to eq("a, b, c")
      expect(described_class.name_list(%w[a b c d e])).to eq("a, b, c, d, e")
    end

    it "names the first five and counts the rest" do
      expect(described_class.name_list(%w[a b c d e f])).to eq("a, b, c, d, e and 1 more")
      expect(described_class.name_list((1..9).map(&:to_s))).to eq("1, 2, 3, 4, 5 and 4 more")
    end

    it "takes another limit" do
      expect(described_class.name_list(%w[a b c], limit: 2)).to eq("a, b and 1 more")
    end

    it "returns an empty string for no items" do
      expect(described_class.name_list([])).to eq("")
    end
  end
end
