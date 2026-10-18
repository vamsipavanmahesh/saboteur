# frozen_string_literal: true

require_relative "../../../lib/dry/inflector/acronyms"

RSpec.describe Dry::Inflector::Acronyms do
  it "answers for mixed case input" do
    expect(described_class.acronym?("Api")).to be(true)
    expect(described_class.acronym?("Html")).to be(true)
    expect(described_class.acronym?("Nope")).to be(false)
  end
end
