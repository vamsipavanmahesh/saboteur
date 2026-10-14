# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Text do
  it "rejects invalid UTF-8 with a parse error naming the problem" do
    expect { described_class.utf8_strict("\xFF".b) }.to raise_error(JSON::ParserError, "invalid UTF-8")
  end

  it "returns valid input retagged as UTF-8" do
    expect(described_class.utf8_strict("ok".b)).to eq("ok")
  end
end
