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

RSpec.describe Saboteur::MutationSource::ConstantLiterals, "arid and selection edges (#319 dogfood)" do
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

  it "honors arid patterns on hash entries and array elements" do
    hash = constant_subject("MAP = { a: 1, b: 2 }.freeze\n")
    expect(described_class.new(arid: ["\\Aa: 1\\z"]).mutations_for(hash).size).to eq(1)
    array = constant_subject("TAGS = [:a, :b]\n")
    expect(described_class.new(arid: ["\\A:a\\z"]).mutations_for(array).size).to eq(1)
  end

  it "names itself builtin, like the other operators" do
    expect(described_class.new.name).to eq("builtin")
  end

  it "proposes nothing for a hash when only element_removal is selected" do
    hash = constant_subject("MAP = { a: 1 }.freeze\n")
    expect(described_class.new(operators: ["element_removal"]).mutations_for(hash)).to be_empty
  end

  # The literal type picks the operator: pair removal on an array (or the
  # reverse) is a category error even when it happens to find nothing.
  it "never asks pair_removal about an array literal" do
    array = constant_subject("TAGS = [:a, :b]\n")
    expect_any_instance_of(Saboteur::MutationSource::PairRemoval).not_to receive(:mutations_for)
    described_class.new.mutations_for(array)
  end

  it "never asks element_removal about a hash literal" do
    hash = constant_subject("MAP = { a: 1, b: 2 }.freeze\n")
    expect_any_instance_of(Saboteur::MutationSource::ElementRemoval).not_to receive(:mutations_for)
    described_class.new.mutations_for(hash)
  end

  # The arid pattern is the regexp and the entry source is the string. With
  # the map on @arid swapped to each, raw strings reach String#match? and
  # the two swap roles - which stays invisible while the pattern's own text
  # contains the entry, so this entry must not quote the pattern verbatim.
  it "matches arid patterns against the entry source, not the other way around" do
    subject = constant_subject("LEVELS = { level: default_logger.level, plain: 1 }.freeze\n")
    source = described_class.new(arid: ["logger"])
    expect(source.mutations_for(subject).size).to eq(1)
  end
end
