# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/people"

RSpec.describe People::Person do
  it "is not an adult at 17" do
    expect(described_class.new(17).adult?).to be(false)
  end

  it "is an adult at 19" do
    expect(described_class.new(19).adult?).to be(true)
  end

  it "compares with the constant" do
    expect(described_class.new(17).adult_by_constant?).to be(false)
    expect(described_class.new(19).adult_by_constant?).to be(true)
  end

  it "builds a person" do
    expect(described_class.build(40).age).to eq(40)
  end

  it "describes itself through a private method" do
    person = described_class.new(30)
    expect(person.describe).to eq("age 30")
    expect(person.private_methods).to include(:label)
  end
end
