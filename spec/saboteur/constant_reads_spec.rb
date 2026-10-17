# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::ConstantReads do
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

  def reads_for(text, constant, filename: "reads.rb", bin: false)
    file = File.join(@root, filename)
    bin ? File.binwrite(file, text) : File.write(file, text)
    Saboteur::ConstantReads.across([file], constant)[file]
  end

  let(:top) { find("RULES = { a: 1 }\n").subjects.first }
  let(:shop) { find("module Shop\n  RULES = { a: 1 }\nend\n").subjects.first }

  it "treats a capture inside a boot-time block as a load read" do
    reads = reads_for("1.times { COPY = RULES }\n", top)
    expect(reads.load).to eq([1])
    expect(reads.runtime).to be_empty
  end

  # The capture flag must reach reads nested inside the captured value:
  # `1.times { COPY = [RULES] }` still resolves RULES while the file loads.
  it "keeps the capture flag when the captured value nests the read" do
    reads = reads_for("1.times { COPY = [RULES] }\n", top)
    expect(reads.load).to eq([1])
    expect(reads.runtime).to be_empty
  end

  it "records the def's own line in defs" do
    reads = reads_for("def m\n  RULES\nend\n", top)
    expect(reads.defs).to eq([1])
    expect(reads.runtime).to eq([2])
  end

  it "classifies a read inside a lambda as runtime" do
    reads = reads_for("f = -> { RULES }\n", top)
    expect(reads.runtime).to eq([1])
    expect(reads.load).to be_empty
  end

  it "ignores reads of a different name in the owning scope" do
    reads = reads_for("module Shop\n  def m = OTHER\n  def n = RULES\nend\n", shop)
    expect(reads.runtime).to eq([3])
  end

  it "walks past an empty def body" do
    reads = reads_for("def m\nend\nRULES\n", top)
    expect(reads.load).to eq([3])
  end

  # `COPY = [RULES, RULES]` reads the constant twice on one line while the
  # file loads; the load list must not repeat the line.
  it "dedupes load reads repeated on one line" do
    reads = reads_for("COPY = [RULES, RULES]\n", top)
    expect(reads.load).to eq([1])
  end

  it "dedupes def lines repeated by two defs on one line" do
    reads = reads_for("def a = RULES; def b = RULES\n", top)
    expect(reads.defs).to eq([1])
  end

  # The capture flag must also cross a block boundary inside the value:
  # `COPY = 1.times { RULES }` still reads RULES while the file loads.
  it "keeps the capture flag through a block inside the captured value" do
    reads = reads_for("COPY = 1.times { RULES }\n", top)
    expect(reads.load).to eq([1])
    expect(reads.runtime).to be_empty
  end

  # Matching compares the path spelling with the constant's id
  # ("Shop::RULES"), not with the subject's inspect string.
  it "matches a qualified read path against the constant id" do
    reads = reads_for("def m = Shop::RULES\n", shop)
    expect(reads.runtime).to eq([1])
  end

  # `RULES::SUB` reads RULES while resolving the path: the read node nested
  # inside the path still counts, so a mutant of RULES is observable there.
  it "records a read of the constant when it appears as a path prefix" do
    reads = reads_for("x = RULES::SUB\n", top)
    expect(reads.load).to eq([1])
  end

  # The constant's own owner scope may write it (`RULES = ...`): reads below
  # the write are not shadowed when the scope IS the owner. The path must
  # keep the full "A::B" spelling for that comparison.
  it "does not shadow reads inside the constant's own nested owner scope" do
    nested = find("module A\n  module B\n    RULES = { a: 1 }\n  end\nend\n").subjects.first
    reads = reads_for("module A\n  module B\n    RULES = { a: 1 }\n    def self.m = RULES\n  end\nend\n", nested)
    expect(reads.runtime).to eq([4])
  end

  it "matches a leading-:: path against the full spelling" do
    reads = reads_for("def m = ::Shop::RULES\n", shop)
    expect(reads.runtime).to eq([1])
  end

  it "ignores a path whose spelling differs" do
    reads = reads_for("def m = Shop::OTHER\ndef n = Shop::RULES\n", shop)
    expect(reads.runtime).to eq([2])
  end

  it "returns no reads for a file that does not parse" do
    expect(reads_for("def m = RULES\ndef broken(\n", top)).to be_nil
  end

  it "matches a bare read inside a scope written with a leading ::" do
    reads = reads_for("class ::Shop::Cart\n  def m = RULES\nend\n", shop)
    expect(reads.runtime).to eq([2])
  end

  it "does not match a scope that only shares a name prefix with the owner" do
    expect(reads_for("module ShopX\n  def m = RULES\nend\n", shop)).to be_nil
  end

  it "records reads in the owner's own nested scope" do
    nested = find("module A\n  module B\n    RULES = { a: 1 }\n  end\nend\n").subjects.first
    reads = reads_for("module A\n  module B\n    def m = RULES\n  end\nend\n", nested)
    expect(reads.runtime).to eq([3])
  end

  it "shadows reads below an outer scope's own write through deeper nesting" do
    expect(reads_for("module A\n  RULES = 1\n  module B\n    def m = RULES\n  end\nend\n", top)).to be_nil
  end

  it "does not shadow when the scope writes a different constant" do
    reads = reads_for("module A\n  OTHER = 1\n  def m = RULES\nend\n", top)
    expect(reads.runtime).to eq([3])
  end

  it "does not shadow on a statement-level read of the constant" do
    reads = reads_for("module A\n  RULES\n  def m = RULES\nend\n", top)
    expect(reads.load).to eq([2])
    expect(reads.runtime).to eq([3])
  end

  it "treats an empty module body as writing nothing" do
    reads = reads_for("module M\nend\ndef m = RULES\n", top)
    expect(reads.runtime).to eq([3])
  end

  it "classifies a statement-level read in a module body as load" do
    reads = reads_for("module Shop\n  p RULES\nend\n", shop)
    expect(reads.load).to eq([2])
    expect(reads.runtime).to be_empty
  end

  it "classifies a block read in a module body as runtime" do
    reads = reads_for("module Shop\n  3.times { RULES }\nend\n", shop)
    expect(reads.runtime).to eq([2])
  end

  it "skips files whose bytes are not valid UTF-8" do
    expect(reads_for("def m = RULES \xFF\n", top, bin: true)).to be_nil
  end

  it "dedupes repeated reads on one line" do
    reads = reads_for("def m = RULES + RULES\n", top)
    expect(reads.runtime).to eq([1])
  end

  describe ".observable_lines" do
    it "adds load lines only for the constant's own file, sorted and unique" do
      constant = instance_double(Saboteur::ConstantSubject, file: "/a/own.rb")
      reads = Saboteur::ConstantReads::Reads.new(runtime: [5], load: [2, 5], defs: [])
      hits = Saboteur::ConstantReads.observable_lines({ "/a/own.rb" => reads, "/a/other.rb" => reads },
                                                      constant)
      expect(hits).to eq("/a/own.rb" => [2, 5], "/a/other.rb" => [5])
    end

    it "drops files with no observable line" do
      constant = instance_double(Saboteur::ConstantSubject, file: "/a/own.rb")
      reads = Saboteur::ConstantReads::Reads.new(runtime: [], load: [2], defs: [])
      hits = Saboteur::ConstantReads.observable_lines({ "/a/other.rb" => reads }, constant)
      expect(hits).to be_empty
    end
  end
end

RSpec.describe Saboteur::ConstantReads, "class << self scopes (#380)" do
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

  def reads_for(text, constant, filename: "reads.rb")
    file = File.join(@root, filename)
    File.write(file, text)
    Saboteur::ConstantReads.across([file], constant)[file]
  end

  let(:sclass_rules) { find("class Host\n  class << self\n    RULES = { a: 1 }\n  end\nend\n").subjects.first }
  let(:host_rules) { find("class Host\n  RULES = { a: 1 }\nend\n").subjects.first }

  it "matches a read inside class << self to the singleton-class constant" do
    reads = reads_for("class Host\n  class << self\n    def m = RULES\n  end\nend\n", sclass_rules)
    expect(reads.runtime).to eq([3])
  end

  it "does not match a class-body read to the singleton-class constant" do
    expect(reads_for("class Host\n  def m = RULES\nend\n", sclass_rules)).to be_nil
  end

  # Constant lookup from the singleton class climbs its ancestors, which
  # include the attached class: a read in `class << self` does observe the
  # attached class's constant.
  it "matches a read inside class << self to the attached class's constant" do
    reads = reads_for("class Host\n  class << self\n    def m = RULES\n  end\nend\n", host_rules)
    expect(reads.runtime).to eq([3])
  end

  # A writing outer scope shadows below it, but entering the constant's
  # owner scope (or its singleton scope) ends the shadow: the owner's own
  # definition is lexically closer there (#395).
  let(:nested_host) { find("module M\n  class Host\n    RULES = { a: 1 }\n  end\nend\n").subjects.first }

  it "clears an outer scope's shadow entering the owner's singleton scope" do
    shadowed_then_owner = "module M\n  RULES = [0]\n  class Host\n    class << self\n      def m = RULES\n    " \
                          "end\n  end\nend\n"
    expect(reads_for(shadowed_then_owner, nested_host).runtime).to eq([5])
  end

  it "clears an outer scope's shadow entering a class owner nested under it" do
    shadowed_then_owner = "module M\n  RULES = [0]\n  class Host\n    def m = RULES\n  end\nend\n"
    expect(reads_for(shadowed_then_owner, nested_host).runtime).to eq([4])
  end

  # M > Host (owner) > Mid (writes RULES) > Deep: the read binds Mid's
  # RULES, not the owner's - Mid's shadow was set INSIDE the owner subtree
  # and must survive deeper nesting (#395 architect review).
  it "keeps an owner-nested writer's shadow through deeper nesting" do
    still_shadowed = "module M\n  RULES = [0]\n  class Host\n    RULES = [1]\n    module Mid\n      " \
                     "RULES = [2]\n      module Deep\n        def m = RULES\n      end\n    end\n  end\nend\n"
    expect(reads_for(still_shadowed, nested_host)).to be_nil
  end

  # A sibling scope's write shadows only below itself: a read in another
  # scope nested under the owner still sees the owner's constant.
  it "clears a sibling scope's shadow for a read nested under the owner (#380)" do
    src = "class Host\n  module Mid\n    RULES = [1]\n  end\n  class Sub\n    def m = RULES\n  end\nend\n"
    expect(reads_for(src, host_rules).runtime).to eq([6])
  end

  it "keeps the shadow below a nested scope under the owner that writes the constant" do
    still_shadowed = "module M\n  RULES = [0]\n  class Host\n    module Mid\n      RULES = [1]\n      " \
                     "def m = RULES\n    end\n  end\nend\n"
    expect(reads_for(still_shadowed, nested_host)).to be_nil
  end

  # The singleton scope's own write IS inside the owner subtree: a class
  # nested under it keeps the shadow - the read binds the singleton's
  # RULES, not the attached class's (#395 dogfood).
  it "keeps a singleton-class write's shadow for a class nested under it" do
    src = "class Host\n  class << self\n    RULES = [9]\n    class Nested\n      def m = RULES\n    end\n  end\nend\n"
    expect(reads_for(src, host_rules)).to be_nil
  end

  # A keyword class SIBLING of class << self does not lexically see the
  # singleton's write: its read still binds the attached class's RULES, so
  # the singleton write's shadow must lift there (#395 dogfood).
  it "lifts a singleton-class write's shadow for a keyword class sibling" do
    src = "class Host\n  RULES = { a: 1 }\n  class << self\n    RULES = [9]\n  end\n  " \
          "class Plain\n    def m = RULES\n  end\nend\n"
    expect(reads_for(src, host_rules).runtime).to eq([7])
  end

  it "lets a singleton-class write shadow the attached class's constant for reads below it" do
    reads = reads_for("class Host\n  class << self\n    RULES = [9]\n    def m = RULES\n  end\nend\n", host_rules)
    expect(reads).to be_nil
  end

  it "matches a read in a keyword class nested in class << self to the singleton-class constant" do
    reads = reads_for("class Host\n  class << self\n    class Nested\n      def m = RULES\n    end\n  end\nend\n",
                      sclass_rules)
    expect(reads.runtime).to eq([4])
  end
end
