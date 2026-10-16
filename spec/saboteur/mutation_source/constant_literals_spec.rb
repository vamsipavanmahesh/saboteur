# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::MutationSource::ConstantLiterals do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def constant_subject(text)
    file = File.join(@root, "constants.rb")
    File.write(file, text)
    Saboteur::ConstantSubjectFinder.new.call(file).subjects.first
  end

  it "applies pair_removal to a constant hash and element_removal to a constant array" do
    hash = constant_subject("MAP = { a: 1, b: 2 }.freeze\n")
    expect(described_class.new.mutations_for(hash).map(&:operator).uniq).to eq(["pair_removal"])
    array = constant_subject("TAGS = [:a, :b]\n")
    expect(described_class.new.mutations_for(array).map(&:operator).uniq).to eq(["element_removal"])
  end

  it "honors operator exclusions" do
    hash = constant_subject("MAP = { a: 1 }\n")
    expect(described_class.new(exclude_operators: ["pair_removal"]).mutations_for(hash)).to be_empty
    array = constant_subject("TAGS = [:a]\n")
    expect(described_class.new(operators: ["pair_removal"]).mutations_for(array)).to be_empty
  end
end
