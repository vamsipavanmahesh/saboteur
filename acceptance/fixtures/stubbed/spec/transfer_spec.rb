require_relative "../lib/transfer"

RSpec.describe Transfer do
  it("converts through the stubbed rate") do
    transfer = described_class.new
    allow(transfer).to receive(:fx_rate).and_return(2)
    expect(transfer.convert(10)).to eq(20)
  end
end
