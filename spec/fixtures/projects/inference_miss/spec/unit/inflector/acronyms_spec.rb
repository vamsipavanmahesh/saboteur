# frozen_string_literal: true

require_relative "../../../lib/dry/inflector/acronyms"

RSpec.describe Dry::Inflector::Acronyms do
  it "knows the acronyms regardless of case" do
    expect(described_class.acronym?("API")).to be(true)
    expect(described_class.acronym?("html")).to be(true)
    expect(described_class.acronym?("plain")).to be(false)
  end
end
