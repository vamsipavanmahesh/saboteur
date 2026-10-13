# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/aliased"

RSpec.describe Aliased do
  it("answers through the alias only") { expect(described_class.new.alias_name).to eq(42) }
end
