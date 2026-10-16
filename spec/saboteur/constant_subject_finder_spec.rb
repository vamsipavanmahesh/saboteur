# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::ConstantSubjectFinder do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def find(text)
    file = File.join(@root, "sample.rb")
    File.write(file, text)
    Saboteur::ConstantSubjectFinder.new.call(file)
  end

  it "finds a frozen constant hash in a module, with its assignment as the span" do
    parsed = find("module Shop\n  RULES = {\n    city: 1\n  }.freeze\nend\n")
    subject = parsed.subjects.first
    expect(subject.id).to eq("Shop::RULES")
    expect(subject.literal_node).to be_a(Prism::HashNode)
    expect(subject.source).to eq("RULES = {\n    city: 1\n  }.freeze")
    expect(subject.skip_reason).to be_nil
    expect(subject.frozen_literals).to be(false)
    expect(parsed.errors).to be_empty
  end

  it "finds a constant array and a top-level constant with no owner" do
    parsed = find("TAGS = [\"a\", \"b\"]\n")
    subject = parsed.subjects.first
    expect(subject.id).to eq("TAGS")
    expect(subject.owner).to be_nil
    expect(subject.literal_node).to be_a(Prism::ArrayNode)
  end

  it "looks through argument-free, block-free calls such as .freeze" do
    parsed = find("N = [1].dup.freeze\n")
    expect(parsed.subjects.first.literal_node).to be_a(Prism::ArrayNode)
  end

  it "carries the frozen_string_literal magic comment" do
    parsed = find("# frozen_string_literal: true\nMAP = { a: 1 }\n")
    expect(parsed.subjects.first.frozen_literals).to be(true)
  end

  it "names a namespaced target, a conditional write and a non-literal value as unsupported" do
    parsed = find("A::B = {}\nMAP ||= []\nDYN = build_map\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:reason)).to eq(["a namespaced target (A::B)",
                                                    "a conditional assignment (||=)",
                                                    "its value is not a hash or array literal"])
  end

  it "treats a class factory as a scope, not as data: constants in its block belong to it" do
    parsed = find("Point = Data.define(:x) do\n  MAP = { a: 1 }\nend\n")
    expect(parsed.unsupported).to be_empty
    subject = parsed.subjects.first
    expect(subject.id).to eq("Point::MAP")
    expect(subject.skip_reason).to eq("defined inside a block")
  end

  it "marks a constant inside a block as skipped, like a def" do
    parsed = find("Class.new do\n  MAP = { a: 1 }\nend\n")
    expect(parsed.subjects.first.skip_reason).to eq("defined inside a block")
  end

  it "reports a file that does not parse" do
    parsed = find("MAP = {\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.errors).not_to be_empty
  end

  describe Saboteur::ConstantReads do
    def read_lines(text, constant)
      file = File.join(@root, "reads.rb")
      File.write(file, text)
      Saboteur::ConstantReads.across([file], constant)[file]
    end

    let(:constant) do
      find("module Shop\n  RULES = { a: 1 }\nend\n").subjects.first
    end

    it "finds bare reads in the owning scope and nested under it" do
      lines = read_lines("module Shop\n  class Cart\n    def m = RULES\n  end\nend\n", constant)
      expect(lines).to eq([3])
    end

    it "finds reads by the full path spelling" do
      lines = read_lines("def m = Shop::RULES\n", constant)
      expect(lines).to eq([1])
    end

    it "ignores reads of a different constant with the same name in a sibling scope" do
      lines = read_lines("module Other\n  def self.m = RULES\nend\n", constant)
      expect(lines).to be_nil
    end

    it "ignores files that never mention the name without parsing them" do
      constant # build before stubbing: its own parse is not the one under test
      allow(Prism).to receive(:parse).and_call_original
      expect(read_lines("X = 1\n", constant)).to be_nil
      expect(Prism).not_to have_received(:parse)
    end

    it "matches a top-level constant anywhere" do
      top = find("RULES = { a: 1 }\n").subjects.first
      lines = read_lines("module Anywhere\n  def self.m = RULES\nend\n", top)
      expect(lines).to eq([2])
    end
  end
end
