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

  # A factory block opens no lexical constant scope: a constant assigned in
  # the block binds on the enclosing lexical scope, never on the class the
  # factory builds (#352).
  it "names a factory-block constant by its lexical owner" do
    parsed = find("module M\n  Point = Data.define(:x) do\n    HELPER = [1]\n  end\nend\n")
    subject = parsed.subjects.first
    expect(subject.id).to eq("M::HELPER")
    expect(subject.skip_reason).to be_nil
  end

  # A `class` keyword inside a factory block re-enters the lexical scope: the
  # class and its constants bind on the enclosing lexical scope, so
  # `FactoryProbe::Nested::RULES` is an ordinary subject, not a phantom
  # `FactoryProbe::Outer::Nested::RULES` skipped as defined inside a
  # block (#352).
  it "names a class declared inside a factory block by its lexical owner" do
    parsed = find("module FactoryProbe\n  Outer = Class.new do\n    class Nested\n      " \
                  "RULES = { a: 1 }\n    end\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["FactoryProbe::Nested::RULES"])
    expect(parsed.subjects.first.skip_reason).to be_nil
    expect(parsed.unsupported).to be_empty
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

  it "treats a class factory as a scope, not as data: a constant in its block binds lexically" do
    parsed = find("Point = Data.define(:x) do\n  MAP = { a: 1 }\nend\n")
    expect(parsed.unsupported).to be_empty
    subject = parsed.subjects.first
    expect(subject.id).to eq("MAP")
    expect(subject.skip_reason).to be_nil
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

  # A keyword class or module re-enters the lexical scope even inside an
  # ordinary block: `class Nested` binds on M, so its constant is an
  # ordinary subject, not one defined inside a block (#352).
  it "treats a constant in a keyword class inside an ordinary block as an ordinary subject" do
    parsed = find("module M\n  1.times do\n    class Nested\n      RULES = { a: 1 }\n    end\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["M::Nested::RULES"])
    expect(parsed.subjects.first.skip_reason).to be_nil
  end

  it "treats a constant in a keyword module inside an ordinary block as an ordinary subject" do
    parsed = find("module M\n  1.times do\n    module Nested\n      RULES = { a: 1 }\n    end\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["M::Nested::RULES"])
    expect(parsed.subjects.first.skip_reason).to be_nil
  end

  it "finds a constant write nested inside a literal value" do
    parsed = find("MAP = { x: (Y = []) }\n")
    expect(parsed.subjects.map(&:id)).to eq(%w[MAP Y])
  end

  it "keeps the factory's receiver and arguments in the enclosing scope" do
    parsed = find("Point = Data.define(FIELDS = [:x]) do\n  HELP = [1]\nend\n")
    help = parsed.subjects.find { |s| s.id == "HELP" }
    expect(help.nesting.last.path).to eq("Point")
    expect(help.nesting.last.kind).to eq(:factory)
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

RSpec.describe Saboteur::ConstantSubjectFinder, "qualified-write identity (#319 lenses)" do
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

  # `RULES = ...` then `::RULES = ...` is one constant assigned twice: the
  # replay ends with the second write, so the first literal must not stay
  # scored. A rooted target names its constant absolutely.
  it "demotes both writes when a rooted target re-assigns the constant" do
    parsed = find("RULES = { a: 1 }\n::RULES = { b: 2 }\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:id).sort).to eq(%w[RULES RULES])
    expect(parsed.unsupported.map(&:reason)).to include("assigned more than once in this file")
  end

  # Inside `module Shop`, the qualified write `Shop::RULES = ...` resolves
  # to the same constant the bare write made a subject.
  it "demotes both writes when a qualified target re-assigns the constant" do
    parsed = find("module Shop\n  RULES = [:a]\n  Shop::RULES = [:b]\nend\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:id).sort).to eq(["Shop::RULES", "Shop::RULES"])
  end

  # The rooted form inside the module must not become "Shop::::Shop::RULES".
  it "demotes both writes when a rooted qualified target re-assigns the constant" do
    parsed = find("module Shop\n  RULES = [:a, :b]\n  ::Shop::RULES = [:c]\nend\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:id).sort).to eq(["Shop::RULES", "Shop::RULES"])
  end
end

RSpec.describe Saboteur::ConstantSubjectFinder, "unrooted qualified writes (#319 round 2)" do
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

  # An unrooted `Shop::RULES` inside `module Outer; module Shop` resolves
  # lexically to Outer::Shop::RULES, so it may overwrite the bare write's
  # constant even though the written slice names a different id.
  it "demotes the literal an unrooted qualified write may overwrite" do
    parsed = find("module Outer\n  module Shop\n    RULES = [:a, :b]\n    Shop::RULES = [:c]\n  end\nend\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:id)).to include("Outer::Shop::RULES", "Shop::RULES")
    expect(parsed.unsupported.find { |u| u.id == "Outer::Shop::RULES" }.reason)
      .to eq("an unrooted qualified write may overwrite it")
  end

  # Same shape with the shortest nesting names.
  it "demotes the literal for a single-letter nesting" do
    parsed = find("module A\n  module B\n    RULES = [:a]\n    B::RULES = [:b]\n  end\nend\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:id)).to include("A::B::RULES", "B::RULES")
  end

  # The write sits one scope out from the literal and still resolves to it.
  it "demotes the nested literal the outer unrooted write may overwrite" do
    parsed = find("module Shop\n  module Inner\n    RULES = [:a]\n  end\n  Inner::RULES = [:b]\nend\n")
    expect(parsed.subjects).to be_empty
    expect(parsed.unsupported.map(&:id)).to include("Shop::Inner::RULES", "Inner::RULES")
  end

  # A rooted target is absolute, so the nested lexical constant is safe.
  it "keeps the nested literal when the qualified write is rooted" do
    parsed = find("module Shop\n  module Inner\n    RULES = [:a]\n  end\n  ::Inner::RULES = [:b]\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["Shop::Inner::RULES"])
    expect(parsed.unsupported.map(&:id)).to eq(["Inner::RULES"])
  end
end

RSpec.describe Saboteur::ConstantSubjectFinder, "class << self owners (#380)" do
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

  # A constant assigned in `class << self` binds on the singleton class:
  # the owner says so, and a same-named constant on the attached class is
  # a different subject.
  it "names a constant in class << self by its singleton-class owner" do
    parsed = find("class Host\n  class << self\n    PLAIN = [1]\n  end\nend\n")
    subject = parsed.subjects.first
    expect(subject.id).to eq("Host.singleton_class::PLAIN")
    expect(subject.skip_reason).to be_nil
  end

  it "keeps same-named constants in the class body and class << self apart" do
    parsed = find("class Host\n  RULES = { a: 1 }\n  class << self\n    RULES = { b: 2 }\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(%w[Host::RULES Host.singleton_class::RULES])
    expect(parsed.unsupported).to be_empty
  end

  it "names a keyword class nested in class << self by its singleton-class owner" do
    parsed = find("class Host\n  class << self\n    class Nested\n      C = [1]\n    end\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["Host.singleton_class::Nested::C"])
  end

  # Unlike a keyword class, `class << self` depends on the runtime self:
  # an `included do` block runs with the including class as self, which is
  # unknowable at parse time, so the constant stays conservatively skipped.
  it "marks a constant in class << self inside a block as skipped" do
    parsed = find("class Host\n  1.times do\n    class << self\n      X = [1]\n    end\n  end\nend\n")
    subject = parsed.subjects.first
    expect(subject.id).to eq("Host.singleton_class::X")
    expect(subject.skip_reason).to eq("defined inside a block")
  end

  # The singleton of a factory's class: the factory block is class_eval'd,
  # so `class << self` there is the generated class's own singleton, and
  # the constant is an ordinary subject like any factory-block def (#352).
  it "names a constant in class << self inside a factory block by the factory's singleton" do
    parsed = find("Point = Data.define(:x) do\n  class << self\n    META = [1]\n  end\nend\n")
    subject = parsed.subjects.first
    expect(subject.id).to eq("Point.singleton_class::META")
    expect(subject.skip_reason).to be_nil
  end

  # `class << other` opens other's singleton, which has no static name, so
  # the constant keeps the enclosing (attached) naming: conservative, and
  # never confused with the self case.
  it "keeps the enclosing owner for a singleton class on a non-self receiver (#380)" do
    parsed = find("class Host\n  other = Object.new\n  class << other\n    X = [1]\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["Host::X"])
  end

  # A singleton class directly inside another has no nameable owner either:
  # the fallback leaves the single enclosing singleton scope in place.
  it "keeps one singleton scope for class << self nested in class << self (#380)" do
    parsed = find("class Host\n  class << self\n    class << self\n      X = [1]\n    end\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["Host.singleton_class::X"])
  end

  it "appends the singleton scope to the innermost owner, not the outermost (#380)" do
    parsed = find("module M\n  class Host\n    class << self\n      RULES = [1]\n    end\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["M::Host.singleton_class::RULES"])
  end

  # The factory scope is consumed by the first `class << self`; a keyword
  # class in between must not let a later one reuse it - the block is
  # class_eval'd, so the keyword class is top-level with its own singleton.
  it "attaches a later class << self to a keyword class, not the enclosing factory (#380)" do
    parsed = find("X = Class.new do\n  class Inner\n    class << self\n      C = [1]\n    end\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["Inner.singleton_class::C"])
  end

  # The factory path already carries the enclosing prefix: appending it to
  # the parts instead of replacing them doubled the owner
  # ("Host::Host::X.singleton_class::M", B builder finding).
  it "does not double the enclosing scope for class << self inside a factory (#395)" do
    parsed = find("class Host\n  X = Class.new do\n    class << self\n      M = [1]\n    end\n  end\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["Host::X.singleton_class::M"])
  end

  # No attached class at the top level: the singleton of the toplevel self
  # has no static name, so the constant keeps its plain top-level name.
  it "names a constant in a top-level class << self at the top level (#380)" do
    parsed = find("class << self\n  X = [1]\nend\n")
    expect(parsed.subjects.map(&:id)).to eq(["X"])
  end
end
