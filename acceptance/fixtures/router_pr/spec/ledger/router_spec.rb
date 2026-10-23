require_relative "../../lib/ledger/router"

RSpec.describe Router do
  it("routes small amounts") { expect(Router.bank_for(1)).to be_a(Symbol) }
end
