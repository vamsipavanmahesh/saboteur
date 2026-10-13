# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/shapes"

RSpec.describe Shapes::Money do
  it("adds") { expect((described_class.new(2) + described_class.new(3)).cents).to eq(5) }
  it("negates") { expect((-described_class.new(7)).cents).to eq(-7) }
  it("indexes digits") { expect(described_class.new(25)[0]).to eq(5) }
  it("compares") do
    expect(described_class.new(1)).to eq(described_class.new(1))
    expect(described_class.new(1)).not_to eq(described_class.new(2))
  end
end

RSpec.describe Shapes::First do
  it("labels") { expect(described_class.new.label).to eq("first-2") }
end

RSpec.describe Shapes::Second do
  it("labels") { expect(described_class.new.label).to eq("second-6") }
end

RSpec.describe Shapes::Conditional do
  it("modes") { expect(described_class.new.mode).to eq(2) }
end

RSpec.describe Shapes::Reopened do
  it("sizes") { expect(described_class.new.size).to eq(8) }
end
