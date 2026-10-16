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

  it "nests the owner path when the constant sits in a class inside a module" do
    parsed = find("module M\n  class C\n    RULES = { a: 1 }\n  end\nend\n")
    expect(parsed.subjects.first.owner).to eq("M::C")
  end

  it "nests the owner path through enclosing modules" do
    parsed = find("module A\n  module B\n    RULES = [1]\n  end\nend\n")
    expect(parsed.subjects.first.id).to eq("A::B::RULES")
    expect(parsed.subjects.first.owner).to eq("A::B")
  end

  # A factory block opens its own scope under the enclosing nesting:
  # constants in the block belong to the factory's class, under its module.
  it "keeps the enclosing module when a factory block opens a scope" do
    parsed = find("module M\n  Point = Data.define(:x) do\n    HELPER = [1]\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to include("M::Point::HELPER")
  end

  it "looks through .freeze calls" do
    parsed = find("N = [1].freeze\n")
    expect(parsed.subjects.first.literal_node).to be_a(Prism::ArrayNode)
  end

  it "rejects a receiver chain that transforms the literal" do
    parsed = find("N = [1].compact.freeze\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.first.reason).to include("not a hash or array literal")
  end

  it "skips a write guarded by if or unless" do
    parsed = find("RULES = [:a] unless defined?(RULES)\nOTHER = [1] if flag\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:reason)).to eq(["guarded by a condition", "guarded by a condition"])
  end

  it "skips a write inside a block-form conditional" do
    parsed = find("if flag\n  RULES = [:a]\nend\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.first.reason).to eq("guarded by a condition")
  end

  it "rejects a constant assigned twice in one file, both times" do
    parsed = find("RULES = [:a]\nRULES = [:b]\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:reason).uniq).to eq(["assigned more than once in this file"])
  end

  it "rejects a literal write when ANY second write overwrites it, not just a literal one (#319)" do
    parsed = find("RULES = { a: 1 }\nRULES = build_rules\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:reason)).to contain_exactly("assigned more than once in this file",
                                                                "its value is not a hash or array literal")

    guarded = find("RULES = { a: 1 }\nRULES = { b: 2 } if flag\n")
    expect(guarded.subjects).to be_empty
    expect(guarded.unsupported.select { |u| u.reason == "assigned more than once in this file" }.size).to eq(1)
  end

  it "keeps same-named constants in different scopes" do
    parsed = find("module A\n  RULES = [:a]\nend\nmodule B\n  RULES = [:b]\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(%w[A::RULES B::RULES])
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
      Saboteur::ConstantReads.across([file], constant)[file]&.runtime
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

    it "classifies statement-level reads as load and def or block reads as runtime" do
      file = File.join(@root, "mixed.rb")
      File.write(file, "COPY = RULES\ndef m = RULES\n3.times { RULES }\n")
      top = find("RULES = { a: 1 }\n").subjects.first
      reads = Saboteur::ConstantReads.across([file], top)[file]
      expect(reads.load).to eq([1])
      expect(reads.runtime).to eq([2, 3])
      expect(reads.defs).to eq([2])
    end

    it "ignores reads shadowed by an inner scope's own constant" do
      lines = read_lines("module Shop\n  class Inner\n    RULES = { b: 2 }\n    def own = RULES\n  end\nend\n",
                         constant)
      expect(lines).to be_nil
    end

    it "still matches the full path spelling under a shadowing scope" do
      lines = read_lines("module Shop\n  class Inner\n    RULES = { b: 2 }\n    def outer = Shop::RULES\n  end\nend\n",
                         constant)
      expect(lines).to eq([4])
    end
  end
end

RSpec.describe Saboteur::ConstantSubjectFinder, "finder edges (#319 dogfood round 2)" do
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

  # Only the frozen_string_literal key freezes: another magic comment
  # whose value is "true" does not. The dashed spelling of the key is the
  # same key - editors write it both ways.
  it "freezes only on the frozen_string_literal key, dashed or not" do
    expect(find("# shareable_constant_value: true\nMAP = { a: 1 }\n").subjects.first.frozen_literals).to be(false)
    expect(find("# frozen-string-literal: true\nMAP = { a: 1 }\n").subjects.first.frozen_literals).to be(true)
  end

  it "reads the frozen_string_literal magic comment both ways" do
    expect(find("# frozen_string_literal: true\nMAP = { a: 1 }\n").subjects.first.frozen_literals).to be(true)
    expect(find("# frozen_string_literal: false\nMAP = { a: 1 }\n").subjects.first.frozen_literals).to be(false)
    expect(find("# frozen_string_literal: yes\nMAP = { a: 1 }\n").subjects.first.frozen_literals).to be(false)
  end

  it "finds a constant nested inside a conditional write's value" do
    parsed = find("MAP ||= (INNER = [1])\n")
    expect(parsed.subjects.map(&:id)).to eq(["INNER"])
    expect(parsed.unsupported.map(&:name)).to eq([:MAP])
  end

  it "finds a constant nested inside a namespaced write's value" do
    parsed = find("Shop::RULES = { a: (INNER = [1]) }\n")
    expect(parsed.subjects.map(&:id)).to eq(["INNER"])
    expect(parsed.unsupported.map(&:name)).to eq(["Shop::RULES"])
  end

  it "resets the nesting at a ::-rooted scope" do
    parsed = find("module Other\n  class ::Shop\n    RULES = { a: 1 }\n  end\nend\n")
    expect(parsed.subjects.first.owner).to eq("Shop")
  end

  it "records the scope kind on the subject's nesting" do
    expect(find("module M\n  RULES = { a: 1 }\nend\n").subjects.first.nesting.map(&:kind)).to eq([:module])
    expect(find("class C\n  RULES = { a: 1 }\nend\n").subjects.first.nesting.map(&:kind)).to eq([:class])
  end

  it "finds a constant nested inside a non-literal value" do
    parsed = find("RULES = (INNER = [1])\n")
    expect(parsed.subjects.map(&:id)).to eq(["INNER"])
    expect(parsed.unsupported.map(&:name)).to eq([:RULES])
  end

  it "keeps the parse error messages" do
    parsed = find("MAP = { a: 1\n")
    expect(parsed.errors).not_to be_empty
    expect(parsed.errors).to all(be_a(String))
  end
end

RSpec.describe Saboteur::ConstantSubjectFinder, "walk branches (#319 dogfood)" do
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

  it "records the scope kind: a module stays a module, a class a class" do
    parsed = find("module M\n  A = [1]\nend\nclass C\n  B = [2]\nend\n")
    expect(parsed.subjects.map { |s| s.nesting.last.kind }).to eq(%i[module class])
  end

  it "walks a constant write hidden in a conditional predicate and in the else arm" do
    parsed = find("if (Y = [1]).any?\n  X = [2]\nelse\n  Z = [3]\nend\n")
    # The predicate runs unconditionally, so Y is a subject; both arms are guarded.
    expect(parsed.subjects.map(&:id)).to eq(%w[Y])
    expect(parsed.unsupported.map { |u| [u.name, u.reason] })
      .to contain_exactly([:X, "guarded by a condition"], [:Z, "guarded by a condition"])
  end

  it "walks both arms of unless/else" do
    parsed = find("unless ok\n  A = [1]\nelse\n  B = [2]\nend\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:name)).to contain_exactly(:A, :B)
  end

  it "marks a constant defined inside a block but still finds it" do
    parsed = find("1.times do\n  X = [1]\nend\n")
    expect(parsed.subjects.first.skip_reason).to eq("defined inside a block")
  end

  it "finds a constant write nested inside a literal value" do
    parsed = find("MAP = { x: (Y = []) }\n")
    expect(parsed.subjects.map(&:id)).to eq(%w[MAP Y])
  end

  it "keeps the factory's receiver and arguments in the enclosing scope" do
    parsed = find("Point = Data.define(FIELDS = [:x]) do\n  HELP = [1]\nend\n")
    point = parsed.subjects.find { |s| s.id == "Point::HELP" }
    expect(point.nesting.last.path).to eq("Point")
    expect(point.nesting.last.kind).to eq(:class)
    expect(parsed.subjects.map(&:id)).to include("FIELDS")
  end

  it "is not a factory scope without a block, with a receiver, or for a non-factory call" do
    expect(find("Point = Data.define(:x)\n").unsupported.map(&:reason))
      .to eq(["its value is not a hash or array literal"])
    expect(find("Point = Geometry::Data.define(:x) do\n  H = [1]\nend\n").unsupported.map(&:reason))
      .to eq(["its value is not a hash or array literal"])
    expect(find("Point = Data.new(:x) do\n  H = [1]\nend\n").unsupported.map(&:reason))
      .to eq(["its value is not a hash or array literal"])
  end

  it "looks through .freeze only: freeze with arguments or a block is not the literal" do
    expect(find("RULES = [1].freeze(true)\n").unsupported.map(&:reason))
      .to eq(["its value is not a hash or array literal"])
    expect(find("RULES = [1].freeze { 2 }\n").unsupported.map(&:reason))
      .to eq(["its value is not a hash or array literal"])
    expect(find("RULES = [1].freeze.freeze\n").subjects.map(&:id)).to eq(["RULES"])
  end

  it "marks string literals frozen when the magic comment says so" do
    parsed = find("# frozen_string_literal: true\nRULES = { a: \"x\" }\n")
    expect(parsed.subjects.first.frozen_literals).to be(true)
  end
end
