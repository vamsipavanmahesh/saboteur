# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::SubjectFinder do
  def ids(source)
    subjects_in(source).map(&:id)
  end

  it "finds instance methods and def self.x with their lexical owner" do
    source = <<~RUBY
      module Outer
        class Person
          def adult?; @age >= 18; end
          def self.build(age) = new(age)
        end
      end
    RUBY
    expect(ids(source)).to eq(["Outer::Person#adult?", "Outer::Person.build"])
  end

  it "treats defs in class << self as singleton methods evaluated on the singleton" do
    subject = subjects_in("class A\n  class << self\n    def make; end\n  end\nend\n").first
    expect([subject.id, subject.singleton, subject.sclass]).to eq(["A.make", true, true])
  end

  it "uses compact class paths and restarts at ::" do
    expect(ids("module X\n  class A::B\n    def m; end\n  end\n  class ::Top\n    def t; end\n  end\nend\n"))
      .to eq(["X::A::B#m", "Top#t"])
  end

  it "finds defs passed to visibility modifiers" do
    expect(ids("class A\n  private def secret; 1; end\n  protected def p; end\nend\n")).to eq(["A#secret", "A#p"])
  end

  it "finds defs under a class-level conditional" do
    expect(ids("class A\n  if true\n    def x; end\n  end\nend\n")).to eq(["A#x"])
  end

  it "does not find top-level defs, nested defs and def obj.x, and marks defs in blocks as skipped" do
    source = <<~RUBY
      def top; end
      class A
        def outer
          def inner; end
        end
        define_method(:dm) { 1 }
        included do
          def in_block; end
        end
        Klass = Class.new do
          def anon; end
        end
        def other.x; end
        class << self
          def self.meta; end
        end
      end
    RUBY
    found = subjects_in(source)
    expect(found.map(&:id)).to eq(["A#outer", "A#dm", "A#in_block", "A::Klass#anon"])
    # define_method with a literal name and a block is a subject (#194), and
    # a Class.new factory block names its class so its defs re-evaluate
    # through Klass.class_eval as ordinary subjects (#290/#339); the
    # `included do` block keeps its defs skipped.
    expect(found.map(&:skip_reason)).to eq([nil, nil, "defined inside a block", nil])
  end

  it "names a def in an anonymous block after the block, not after the file" do
    source = "class A\n  included do\n    def in_block; end\n  end\nend\n" \
             "Cart = Struct.new(:a) do\n  def total = a\nend\n"
    found = subjects_in(source)
    expect(found.map { |subject| [subject.id, subject.skip_reason] })
      .to eq([["A#in_block", "defined inside a block"], ["Cart#total", nil]])
  end

  it "records byte offsets and lines of the whole def" do
    source = "# héllo\nclass A\n  def m\n    1\n  end\nend\n"
    subject = subjects_in(source).first
    expect(subject.source).to eq("def m\n    1\n  end")
    expect([subject.start_line, subject.end_line]).to eq([3, 5])
    expect(source.b.byteslice(subject.start_byte, 3)).to eq("def")
  end

  it "notes a frozen_string_literal magic comment" do
    expect(subjects_in("# frozen_string_literal: true\nclass A\n  def m; end\nend\n").first.frozen_literals).to be(true)
    expect(subjects_in("class A\n  def m; end\nend\n").first.frozen_literals).to be(false)
  end

  it "marks subjects in files that use refinements as skipped" do
    subject = subjects_in("module R\n  using Something\n  class A\n    def m; end\n  end\nend\n").first
    expect(subject.skip_reason).to eq("refinements")
  end

  it "returns parse errors instead of subjects for invalid Ruby" do
    dir = Dir.mktmpdir
    path = File.join(dir, "bad.rb")
    File.write(path, "class A\n  def m(\nend\n")
    parsed = described_class.new.call(path)
    expect(parsed.subjects).to be_empty
    expect(parsed.errors).not_to be_empty
  ensure
    FileUtils.rm_rf(dir)
  end

  it "attaches a sorbet sig sitting right before the def to the subject" do
    subject = subject_named(
      "class SigTarget\n  sig { params(a: Integer).returns(Integer) }\n  def fee(a)\n    a\n  end\nend\n",
      "SigTarget#fee"
    )
    expect(subject.sig_source).to eq("sig { params(a: Integer).returns(Integer) }")
  end

  it "attaches a T.sig call the same way" do
    subject = subject_named("class TSigTarget\n  T.sig { void }\n  def m\n  end\nend\n", "TSigTarget#m")
    expect(subject.sig_source).to eq("T.sig { void }")
  end

  it "leaves sig_source nil without a sig, or with one that belongs to another def" do
    plain = subject_named("class PlainTarget\n  def m\n  end\nend\n", "PlainTarget#m")
    expect(plain.sig_source).to be_nil
    separated = subject_named("class SepTarget\n  sig { void }\n  def other\n  end\n\n  def m\n  end\nend\n",
                              "SepTarget#m")
    expect(separated.sig_source).to be_nil
  end
  it "does not attach unrelated calls, blockless sigs or another receiver's sig" do
    ["other { void }", "sig", "Other.sig { void }"].each do |call|
      target = subject_named("class SigReject\n  #{call}\n  def m\n  end\nend\n", "SigReject#m")
      expect(target.sig_source).to be_nil
    end
  end

  it "names a def in a top-level block with a placeholder owner" do
    found = subjects_in("included do\n  def hook; end\nend\n")
    expect(found.map(&:id)).to eq(["(anonymous block)#hook"])
    expect(found.first.skip_reason).to eq("defined inside a block")
  end

  it "finds a block that is an argument of a constant's value" do
    found = subjects_in("class A\n  BOX = wrap(Class.new do\n    def inside; end\n  end)\nend\n")
    expect(found.map { |subject| [subject.id, subject.skip_reason] }).to eq([["A#inside", "defined inside a block"]])
  end

  it "names the owner for each core class factory, and only for those" do
    {
      "Data.define(:a)" => true, "Struct.new(:a)" => true, "Class.new" => true, "Module.new" => true,
      "Data.new(:a)" => false, "Struct.define(:a)" => false, "Class.define" => false,
      "Factory.define(:a)" => false, "Other::Data.define(:a)" => false, "build(:a)" => false,
      "Data.define(:a).itself" => false
    }.each do |call, owned|
      found = subjects_in("Thing = #{call} do\n  def m; end\nend\n")
      expect(found.map(&:id)).to eq([owned ? "Thing#m" : "(anonymous block)#m"]), call
      # Owned factory defs are subjects (#290); a def in any other block is
      # still skipped.
      expect(found.first.skip_reason).to eq(owned ? nil : "defined inside a block"), call
    end
  end

  it "still skips a def inside a non-factory block nested in a factory block" do
    found = subjects_in("Thing = Class.new do\n  included do\n    def m; end\n  end\nend\n")
    expect(found.map { |subject| [subject.id, subject.skip_reason] })
      .to eq([["Thing#m", "defined inside a block"]])
  end

  it "still skips a factory def when the factory itself sits in a block" do
    found = subjects_in("class A\n  included do\n    X = Data.define(:a) do\n      def m; end\n    end\n  end\nend\n")
    expect(found.map { |subject| [subject.id, subject.skip_reason] })
      .to eq([["A::X#m", "defined inside a block"]])
  end

  it "keeps an argument's block in the enclosing scope next to the factory's own block" do
    source = "Thing = Class.new(Base.build do\n  def arg_def; end\nend) do\n  def own_def; end\nend\n"
    expect(subjects_in(source).map(&:id)).to eq(["(anonymous block)#arg_def", "Thing#own_def"])
    nested = subjects_in("class A\n  Thing = Class.new(wrap { def arg_def; end }) { def own_def; end }\nend\n")
    expect(nested.map(&:id)).to eq(["A#arg_def", "A::Thing#own_def"])
  end

  it "does not give a block argument (&-> { }) the factory's new class as owner" do
    found = subjects_in("Thing = Class.new(&-> { def m; end })\n")
    expect(found.map(&:id)).to eq(["(anonymous block)#m"])
    expect(found.first.skip_reason).to eq("defined inside a block")
  end

  it "keeps walking a factory call that has no block of its own" do
    found = subjects_in("Thing = Class.new(Base.build do\n  def m; end\nend)\n")
    expect(found.map { |subject| [subject.id, subject.skip_reason] })
      .to eq([["(anonymous block)#m", "defined inside a block"]])
  end

  it "keeps the enclosing owner for a block that is not a class factory" do
    found = subjects_in("class A\n  Thing = Factory.define(:a) do\n    def m; end\n  end\nend\n")
    expect(found.map(&:id)).to eq(["A#m"])
  end

  it "does not name a qualified constant target after a guessed owner" do
    found = subjects_in("class A\n  B::Thing = Struct.new(:a) do\n    def m; end\n  end\nend\n")
    expect(found.map(&:id)).to eq(["A#m"])
  end

  it "nests a factory-defined class under the enclosing scope" do
    found = subjects_in("module Outer\n  Point = Data.define(:x) do\n    def m; end\n  end\nend\n")
    expect(found.map(&:id)).to eq(["Outer::Point#m"])
  end

  it "binds a nested factory constant to the enclosing lexical scope, not the generated class (#339)" do
    # Constant assignment in a block is lexical: Inner lives on FactoryProbe,
    # never on the generated FactoryProbe::Outer.
    found = subjects_in(<<~RUBY)
      module FactoryProbe
        Outer = Class.new do
          Inner = Data.define(:v) do
            def value = v
          end
        end
      end
    RUBY
    expect(found.map(&:id)).to eq(["FactoryProbe::Inner#value"])
  end

  it "binds a factory nested in a nested factory to the enclosing lexical scope (#339)" do
    found = subjects_in(<<~RUBY)
      module FactoryProbe
        A = Class.new do
          B = Class.new do
            C = Data.define(:x) do
              def v = x
            end
          end
        end
      end
    RUBY
    expect(found.map(&:id)).to eq(["FactoryProbe::C#v"])
  end

  it "binds a factory nested under a keyword class in a factory to that class (#339)" do
    found = subjects_in(<<~RUBY)
      module FactoryProbe
        Outer = Class.new do
          class Real
            B = Struct.new(:x) do
              def v = x
            end
          end
        end
      end
    RUBY
    expect(found.map(&:id)).to eq(["FactoryProbe::Real::B#v"])
  end

  it "binds a keyword class declared in a factory block to the enclosing lexical scope (#339)" do
    found = subjects_in(<<~RUBY)
      module FactoryProbe
        Outer = Class.new do
          class Nested
            def x = 1
          end
        end
      end
    RUBY
    expect(found.map(&:id)).to eq(["FactoryProbe::Nested#x"])
  end

  it "binds a keyword module declared in a factory block to the enclosing lexical scope (#339)" do
    found = subjects_in(<<~RUBY)
      module FactoryProbe
        Outer = Module.new do
          module Nested
            def x = 1
          end
        end
      end
    RUBY
    expect(found.map(&:id)).to eq(["FactoryProbe::Nested#x"])
  end

  it "binds a Module.new factory nested in a factory block to the enclosing lexical scope (#339)" do
    found = subjects_in(<<~RUBY)
      module FactoryProbe
        Outer = Class.new do
          M = Module.new do
            def x = 1
          end
        end
      end
    RUBY
    expect(found.map(&:id)).to eq(["FactoryProbe::M#x"])
  end

  it "keeps walking a constant assigned to a plain value" do
    expect(ids("class A\n  LIMIT = 3\n  def m; end\nend\n")).to eq(["A#m"])
  end

  it "makes define_method with a block a subject of the enclosing owner (#194)" do
    source = <<~RUBY
      module Outer
        class Person
          define_method(:adult?) { @age >= 18 }
        end
      end
    RUBY
    expect(ids(source)).to eq(["Outer::Person#adult?"])
  end

  it "accepts a do...end block and a string name for define_method (#194)" do
    source = <<~RUBY
      class A
        define_method("m") do |x|
          x * 2
        end
      end
    RUBY
    expect(ids(source)).to eq(["A#m"])
  end

  it "treats define_method inside class << self as a singleton subject (#194)" do
    source = <<~RUBY
      class A
        class << self
          define_method(:build) { new }
        end
      end
    RUBY
    found = subjects_in(source)
    expect(found.map { |subject| [subject.id, subject.singleton, subject.sclass] }).to eq([["A.build", true, true]])
  end

  it "skips define_method in a block whose owner is unknown, keeping the reason (#194)" do
    source = <<~RUBY
      class A
        included do
          define_method(:m) { 1 }
        end
      end
    RUBY
    found = subjects_in(source)
    expect(found.map { |subject| [subject.id, subject.skip_reason] }).to eq([["A#m", "defined inside a block"]])
  end

  it "walks past a call with an empty block without tripping on the nil body (#194)" do
    # The empty block's body is nil; the nil guard in walk must return
    # instead of letting nil reach the child-walk.
    expect(ids("class A\n  def m; end\nend\nconfigure { }\n")).to eq(["A#m"])
  end
  it "ignores define_method with a name it cannot read, and without a block (#194)" do
    expect(ids("class A\n  define_method(name) { 1 }\nend\n")).to eq([])
    expect(ids("class A\n  define_method(:m, -> { 1 })\nend\n")).to eq([])
    expect(ids("class A\n  define_method(:m)\nend\n")).to eq([])
    expect(ids("class A\n  define_method { 1 }\nend\n")).to eq([])
  end

  it "ignores a two-argument define_method: the block is dead code there (#194)" do
    expect(ids("class A\n  define_method(:m, proc { 7 }) { 8 }\nend\n")).to eq([])
  end

  it "ignores a block call that is not define_method, even with a symbol argument (#194)" do
    expect(ids("class A\n  foo(:m) { 1 }\nend\n")).to eq([])
  end

  it "skips define_method in a top-level block with the anonymous owner (#194)" do
    found = subjects_in("included do\n  define_method(:m) { 1 }\nend\n")
    expect(found.map { |subject| [subject.id, subject.skip_reason] })
      .to eq([["(anonymous block)#m", "defined inside a block"]])
  end

  it "ignores define_method with an explicit receiver (#194)" do
    expect(ids("class A\n  mod.define_method(:m) { 1 }\nend\n")).to eq([])
  end

  it "drops a top-level define_method with no owner, like a top-level def (#194)" do
    expect(ids("define_method(:m) { 1 }\n")).to eq([])
  end

  # A factory constant assigned inside class << self binds on the singleton
  # class (#352): two unrelated classes each get their own method, so the
  # subjects must not share one id (#406). Mirrors the constant-side
  # singleton_class rendering (#380).
  it "gives a factory def inside class << self a singleton_class owner, distinct from the class-body twin" do
    source = <<~RUBY
      class Host
        Widget = Data.define(:count) do
          def doubled = count * 100
        end
        class << self
          Widget = Data.define(:count) do
            def doubled = count * 2
          end
        end
      end
    RUBY
    found = subjects_in(source)
    expect(found.map(&:id)).to eq(["Host::Widget#doubled", "Host.singleton_class::Widget#doubled"])
    expect(found.map { |subject| [subject.singleton, subject.sclass] }).to eq([[false, false], [false, false]])
  end

  # The sclass segment consults only scopes AFTER it for a factory (#430
  # dogfood pins): a factory before the sclass never justifies the
  # singleton_class segment, so the slice start must stay index + 1 -
  # a start at index - 1 or at 1 pulls the earlier factory into the check.
  it "drops the sclass segment when a top-level factory wraps the sclass" do
    source = <<~RUBY
      Widget = Data.define(:count) do
        class << self
          def doubled = count * 2
        end
      end
    RUBY
    expect(subjects_in(source).map(&:id)).to eq(["Widget.doubled"])
  end

  it "drops the sclass segment when a namespaced factory wraps the sclass" do
    source = <<~RUBY
      class Host
        Widget = Data.define(:count) do
          class << self
            def doubled = count * 2
          end
        end
      end
    RUBY
    expect(subjects_in(source).map(&:id)).to eq(["Host::Widget.doubled"])
  end

  # A `class << self` inside a factory block attaches to the factory's
  # class at runtime (class_eval sets self), so a factory assigned there
  # binds on Host::W.singleton_class, not on Host.singleton_class (#438):
  # the stripped factory scope must stay visible to the sclass attachment.
  it "attaches an sclass inside a factory block to the factory class's singleton (#438)" do
    source = <<~RUBY
      class Host
        W = Data.define(:c) do
          class << self
            V = Data.define(:d) { def n = d }
          end
        end
      end
    RUBY
    expect(subjects_in(source).map(&:id)).to eq(["Host::W.singleton_class::V#n"])
  end

  # An outer factory scope dropped from the path must be judged only on
  # scopes AFTER it: a class << self that ENCLOSES the factory is not
  # inside it, so it cannot keep the factory in the path. A slice start
  # at 1 or at index - 1 pulls that earlier sclass into the check (#555
  # dogfood).
  it "drops an outer factory with no sclass of its own, even inside class << self (#555)" do
    source = <<~RUBY
      class Host
        class << self
          A = Data.define(:x) do
            B = Data.define(:y) do
              def n = y
            end
          end
        end
      end
    RUBY
    expect(subjects_in(source).map(&:id)).to eq(["Host.singleton_class::B#n"])
  end

  # #339 preserved: a factory scope with no sclass inside still opens no
  # lexical constant scope, so a def in a plain factory block names the
  # factory class only.
  it "keeps stripping a factory scope that encloses no sclass (#339)" do
    source = <<~RUBY
      class Host
        W = Data.define(:c) do
          def n = c
        end
      end
    RUBY
    expect(subjects_in(source).map(&:id)).to eq(["Host::W#n"])
  end
end
