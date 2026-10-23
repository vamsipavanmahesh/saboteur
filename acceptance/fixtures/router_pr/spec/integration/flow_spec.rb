require_relative "../../lib/ledger/router"

RSpec.describe "payment flow" do
  it("routes large amounts") { expect(Router.bank_for(6_000_000)).to eq(:hdfc) }
  it("keeps the limit itself") { expect(Router.bank_for(5_000_000)).to eq(:icici) }
end
