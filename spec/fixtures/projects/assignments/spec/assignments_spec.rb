require_relative "../lib/assignments"
RSpec.describe Assignments do
  it("checks addition") { expect(described_class.new.checked(3)).to eq(4) }
  it("checks only zero") { expect(described_class.new.unchecked(0)).to eq(0) }
end
