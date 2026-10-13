require_relative "../lib/coverage_syntax"

RSpec.describe CoverageSyntax do
  it("greets") { expect(described_class.new.message("Ruby")).to eq("Hello Ruby!\n") }
  it("charges") { expect(described_class.new.route(type: "charge")).to eq(:charged) }
  it("refunds") { expect(described_class.new.route(type: "refund")).to eq(:refunded) }
  it("rejects an unknown event") { expect(described_class.new.route(type: "other")).to eq(:unknown) }
  it("rejects an empty event") { expect(described_class.new.route({})).to eq(:unknown) }
end
