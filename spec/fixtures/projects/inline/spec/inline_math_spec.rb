require_relative "../lib/inline_math"
RSpec.describe InlineMath do
  it("doubles") { expect(described_class.new.double(3)).to eq(6) }
end
