require_relative "../lib/conditions"
RSpec.describe Conditions do
  it("checks the result") { expect(described_class.new.checked(true)).to eq(1) }
  it("checks only its type") { expect(described_class.new.unchecked(true)).to be_a(Integer) }
end
