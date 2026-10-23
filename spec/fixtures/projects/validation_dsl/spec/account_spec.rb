require_relative "../lib/account"

RSpec.describe Account do
  it "applies the class-body validations" do
    expect(described_class.new(name: nil, age: 0)).not_to be_valid
    expect(described_class.new(name: "Ada", age: 21)).to be_valid
  end

  it "has a method the CLI can mutate as a positive control" do
    expect(described_class.new.adult?).to be(true)
  end
end
