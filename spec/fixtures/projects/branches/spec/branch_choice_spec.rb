require_relative "../lib/branch_choice"

RSpec.describe BranchChoice do
  it("chooses the first arm") { expect(described_class.new.choose(true)).to eq(10) }
  it("chooses the inner first arm") { expect(described_class.new.nested(true, true)).to eq(30) }
  it("takes both first") { expect(described_class.new.both(true)).to eq(60) }
  it("takes both second") { expect(described_class.new.both(false)).to eq(70) }
  it("does not evaluate the right operand") { expect(described_class.new.short(false)).to eq(false) }
end
