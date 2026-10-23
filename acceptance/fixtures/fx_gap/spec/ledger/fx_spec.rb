require_relative "../../lib/ledger/fx"

RSpec.describe Fx do
  it("converts zero") { expect(Fx.convert(0)).to eq(0) }
end
