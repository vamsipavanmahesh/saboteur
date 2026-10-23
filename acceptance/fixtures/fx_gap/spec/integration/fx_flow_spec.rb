require_relative "../../lib/ledger/fx"

RSpec.describe "fx flow" do
  it("converts positive amounts") { expect(Fx.convert(10)).to be > 0 }
end
