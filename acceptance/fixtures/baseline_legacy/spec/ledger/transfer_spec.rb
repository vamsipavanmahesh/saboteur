require_relative "../../lib/ledger/transfer"

RSpec.describe Ledger::Transfer do
  it("divides the amount") { expect(described_class.new(100).safe_ratio(10)).to eq(10) }
end
