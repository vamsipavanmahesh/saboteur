require_relative "../lib/ranges"
RSpec.describe Ranges do
  it("checks the boundary") { expect(described_class.new.checked(3)).to eq(true) }
  it("checks only the interior") { expect(described_class.new.unchecked(2)).to eq(true) }
end
