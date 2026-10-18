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

  # #194, narrowed to the two shapes the human-essentials dogfood exposed:
  # a bare `scope` call with a literal name and a lambda body defines a
  # singleton method, as does define_singleton_method. Both become singleton
  # subjects whose whole call re-evaluates on the owner, the way a
  # define_method subject's call does today.
  it "finds call-defined singleton methods" do
    {
      "scope :alphabetical, -> { order(:name) }" => "Model.alphabetical",
      "define_singleton_method(:build) { new }" => "Model.build",
      "define_singleton_method(:pull, -> { 1 })" => "Model.pull"
    }.each do |call, id|
      found = subjects_in("class Model\n  #{call}\nend\n")
      # The dotted id asserts the singleton attribution.
      expect(found.map { |subject| [subject.id, subject.skip_reason] }).to eq([[id, nil]]), call
    end
  end

  # sclass is a raw attr_reader on Subject: the || false normalization in
  # walk_call must hold so a call-defined subject with no nesting at all
  # (a top-level block) reads false, not nil (#571 dogfood, successor of
  # stale ignore 4aded400397da9fe).
  it "pins sclass to false, not nil, for a call-defined subject without nesting" do
    subject = subjects_in("1.times do\n  define_method(:m) { 1 }\nend\n").first
    expect(subject.sclass).to be(false)
  end

  it "rejects call shapes that do not define a method body" do
    [
      "before_action :check",          # symbol-only call defines nothing here
      "scope :x, body",                # body must be a lambda literal
      "scope dynamic_name, -> { 1 }",  # the name must be a literal
      "scope :x, -> { 1 }, extra",     # unknown extra arguments
      "Model.scope :x, -> { 1 }",      # an explicit receiver is not a bare DSL call
      "scope :x do 1 end",             # a block-bodied scope is not a Rails scope
      "define_singleton_method(:x, \"body\")", # a computed body is not a block or lambda
      "define_singleton_method(:x)" # a name without a body defines nothing (#571)
    ].each do |call|
      expect(subjects_in("class Model\n  def check; end\n  #{call}\nend\n").map(&:id))
        .to eq(["Model#check"]), call
    end
  end

  it "rejects scope calls that carry more than a literal name and one lambda" do
    [
      "scope :x, -> { 1 }, -> { 2 }",  # the second argument must be the only lambda
      "scope :x, -> { 1 } do 2 end"    # a block-bodied call is not a lambda-bodied scope
    ].each do |call|
      expect(subjects_in("class Model\n  #{call}\nend\n").map(&:id)).to eq([]), call
    end
  end

  # An arg-less call reaches every predicate with node.arguments == nil:
  # the graceful nil skip must stay a skip, not a NoMethodError (#571
  # dogfood survivors). literal_name? guards the public path first, so the
  # lambda_body?/block_only? guards are pinned directly as well.
  it "rejects arg-less calls instead of raising" do
    %w[
      define_method
      define_singleton_method
      scope
    ].each do |call|
      expect(subjects_in("class Model\n  def check; end\n  #{call}\nend\n").map(&:id))
        .to eq(["Model#check"]), call
    end
  end

  it "answers false for arg-less call nodes in every definition predicate" do
    bare = Prism.parse("scope").value.statements.body.first
    blocked = Prism.parse("define_method { 1 }").value.statements.body.first
    finder = described_class.new
    expect(finder.send(:literal_name?, bare)).to be(false)
    expect(finder.send(:lambda_body?, bare)).to be(false)
    expect(finder.send(:block_only?, bare)).to be(false)
    expect(finder.send(:block_only?, blocked)).to be(false)
  end

  # A name-only define_singleton_method carries no body at all: block_only?
  # must not wave it through on the argument count alone (#571 dogfood
  # survivor 18b81f2323de4f26).
  it "answers false for a name-only define_singleton_method in block_only?" do
    node = Prism.parse("define_singleton_method(:x)").value.statements.body.first
    expect(described_class.new.send(:block_only?, node)).to be(false)
  end

  it "exposes a call-defined subject's body: the block for define_method, the lambda for scope and the lambda form" do
    dm = subjects_in("class A\n  define_method(:dm) { 1 }\nend\n").first
    scope = subjects_in("class Model\n  scope :x, -> { order(:name) }\nend\n").first
    dsm = subjects_in("class A\n  define_singleton_method(:pull, -> { 2 })\nend\n").first
    expect(dm.body_node.slice).to eq("1")
    expect(scope.body_node.slice).to eq("order(:name)")
    expect(dsm.body_node.slice).to eq("2")
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

  # #634: a `using` activates its refinement from where it sits to the end
  # of its own scope only. Subjects before it or in sibling scopes are
  # unaffected (the kaminari shape: a `using` in one module must not skip
  # another module's subjects).
  it "skips only subjects lexically after a using in the same or an enclosing scope" do
    found = subjects_in(<<~RUBY)
      module Alpha
        def a_before; 1; end
        using Something
        def a_after; 2; end
      end
      module Beta
        def b_m; 3; end
      end
    RUBY
    expect(found.map { |subject| [subject.id, subject.skip_reason] })
      .to eq([["Alpha#a_before", nil], ["Alpha#a_after", "refinements"], ["Beta#b_m", nil]])
  end

  it "lets a top-level using skip the rest of the file, including nested scopes" do
    found = subjects_in(<<~RUBY)
      module Early
        def e_m; 1; end
      end
      using Something
      module Late
        def l_m; 2; end
        class Nested
          def n_m; 3; end
        end
      end
    RUBY
    expect(found.map { |subject| [subject.id, subject.skip_reason] })
      .to eq([["Early#e_m", nil], ["Late#l_m", "refinements"], ["Late::Nested#n_m", "refinements"]])
  end

  # #634 round 2: activation is lexical, not namespaced. A `class ::Q`
  # nested in the body still runs under the refinement (a constant-path
  # restart does not open a new lexical scope), while a reopened body
  # with the same path after the scope's `end` is a fresh scope.
  it "covers a constant-path restart nested in the using's scope" do
    found = subjects_in(<<~RUBY)
      module A
        using Something
        class ::Q
          def q_m; 1; end
        end
      end
    RUBY
    expect(found.map { |subject| [subject.id, subject.skip_reason] }).to eq([["Q#q_m", "refinements"]])
  end

  it "does not cover reopened bodies or compact paths after the scope's end" do
    found = subjects_in(<<~RUBY)
      module R
        using Something
      end
      module R
        def r_m; 1; end
      end
      class R::C
        def c_m; 2; end
      end
    RUBY
    expect(found.map { |subject| [subject.id, subject.skip_reason] })
      .to eq([["R#r_m", nil], ["R::C#c_m", nil]])
  end

  it "keeps the whole-file skip for a using inside a method or block body" do
    in_def = subjects_in(<<~RUBY)
      module A
        def a_m; using Something; end
        def b_m; 2; end
      end
      module B
        def c_m; 3; end
      end
    RUBY
    expect(in_def.map(&:skip_reason)).to eq(["refinements"] * 3)

    in_block = subjects_in("1.times { using Something }\nmodule B\n  def c_m; 3; end\nend\n")
    expect(in_block.map(&:skip_reason)).to eq(["refinements"])
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

RSpec.describe Saboteur::SubjectFinder, "class_eval heredocs (#544)" do
  def ids(source)
    subjects_in(source).map(&:id)
  end

  it "finds defs in a non-interpolated class_eval heredoc under the enclosing owner" do
    source = <<~RUBY
      class Token
        class_eval <<-CODE
          def expired?
            @expires_at < Time.now
          end
        CODE
      end
    RUBY
    subject = subject_named(source, "Token#expired?")
    expect(subject.source).to start_with("def expired?")
    expect(subject.source).to include("@expires_at < Time.now")
    expect([subject.start_line, subject.end_line]).to eq([3, 5])
  end

  it "names the full lexical nesting for a module_eval heredoc and applies mutants to the real file bytes" do
    source = <<~RUBY
      module Outer
        class Inner
          module_eval <<-CODE
            def self.build
              new
            end
          CODE
        end
      end
    RUBY
    subject = subject_named(source, "Outer::Inner.build")
    expect(subject.singleton).to be(true)
    texts = mutated_texts(subject)
    expect(texts).not_to be_empty
    texts.map(&:last).each { |text| expect(Prism.parse(text).success?).to be(true) }
    expect(texts.map(&:last)).to all(start_with("def self.build"))
    expect(texts.map(&:last)).not_to include(subject.source)
  end

  it "leaves an interpolated heredoc to the code-in-strings warning (#467)" do
    source = <<~'RUBY'
      class Token
        class_eval <<-CODE
          def #{name}
            1
          end
        CODE
      end
    RUBY
    expect(ids(source)).to eq([])
  end

  it "leaves a quoted string argument and an explicit receiver out of this slice" do
    expect(ids("class A\n  class_eval \"def x; end\"\nend\n")).to eq([])
    expect(ids("class A\n  B.class_eval <<-CODE\n    def y; end\n  CODE\nend\n")).to eq([])
  end

  it "leaves instance_eval, a block form, extra arguments, a bare call and a non-string argument alone" do
    expect(ids("class A\n  instance_eval <<-CODE\n    def m; end\n  CODE\nend\n")).to eq([])
    expect(ids("class A\n  class_eval(\"def n; end\") { }\nend\n")).to eq([])
    expect(ids("class A\n  class_eval \"def o; end\", \"other.rb\"\nend\n")).to eq([])
    expect(ids("class A\n  class_eval\nend\n")).to eq([])
    expect(ids("class A\n  class_eval :not_a_string\nend\n")).to eq([])
  end

  it "leaves a block form with a heredoc argument alone (#568)" do
    expect(ids("class A\n  class_eval(<<-CODE) { }\n    def x; end\n  CODE\nend\n")).to eq([])
  end

  it "leaves extra arguments after a heredoc alone (#568)" do
    expect(ids("class A\n  class_eval <<-CODE, \"other.rb\"\n    def y; end\n  CODE\nend\n")).to eq([])
  end

  it "finds defs when the heredoc terminator sits at column 0 (#568)" do
    expect(ids("class A\n  class_eval <<-CODE\n    def z; end\nCODE\nend\n")).to eq(["A#z"])
  end

  it "finds defs with a non-ASCII heredoc terminator at column 0 (#568)" do
    expect(ids("class A\n  class_eval \u003c\u003c-\u00c9\u00c9\n    def z; end\n\u00c9\u00c9\nend\n")).to eq(["A#z"])
  end

  it "registers nothing when a dangling operator swallows the column-0 terminator's first byte (#568)" do
    expect(ids("class A\n  class_eval <<-CODE\n    def z = 1 +\nCODE\nend\n")).to eq([])
  end

  it "finds defs with a quoted punctuation heredoc terminator at column 0 (#568)" do
    expect(ids("class A\n  class_eval <<-'!'\n    def z; end\n!\nend\n")).to eq(["A#z"])
  end

  it "registers nothing from a heredoc body that does not parse" do
    expect(ids("class A\n  class_eval <<-CODE\n    def broken(\n  CODE\nend\n")).to eq([])
  end
end

# Kill recipes for the subject_finder dogfood survivors (#338): each spec
# names the behavior a surviving mutant broke.
RSpec.describe Saboteur::SubjectFinder, "dogfood survivor kills (#338)" do
  def ids(source)
    subjects_in(source).map(&:id)
  end

  # Dropping the `filepath:` kwarg empties SourceFileNode#filepath
  # (`__FILE__`) in the returned AST.
  it "parses with the file path so __FILE__ nodes carry it" do
    subjects = described_class.new.call("named.rb", source: "class A\n  def m\n    __FILE__\n  end\nend\n")
    expect(subjects.subjects.first.node.body.body.first.filepath).to eq("named.rb")
  end

  # map -> each on the parse errors returns ParseError objects, not messages.
  it "returns error messages, not ParseError objects, for invalid Ruby" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.rb")
      File.write(path, "class A\n  def m(\nend\n")
      parsed = described_class.new.call(path)
      expect(parsed.errors).to all(be_a(String))
      expect(parsed.errors.first).to match(/expected|unexpected/i)
    end
  end

  # node.nil? -> false walks a nil body (empty class) and raises in the
  # else branch.
  it "finds no subjects in an empty class or module body" do
    expect(ids("class Empty\nend\nmodule AlsoEmpty\nend\n")).to eq([])
  end

  # Dropping `nesting +` on the module branch loses the outer scope of a
  # def nested through a module.
  it "keeps the outer class in the owner path of a def nested in a module" do
    expect(ids("class Outer\n  module M\n    def m; end\n  end\nend\n")).to eq(["Outer::M#m"])
  end

  # Dropping node.receiver.nil? treats `obj.using X` as a refinement
  # activation.
  it "does not treat `obj.using X` with an explicit receiver as a refinement" do
    found = subjects_in("module B\n  def b_m; end\nend\nclass A\n  obj.using(B)\n  def a_m; end\nend\n")
    expect(found.map { |subject| [subject.id, subject.skip_reason] })
      .to eq([["B#b_m", nil], ["A#a_m", nil]])
  end

  # walk_singleton_class guards: defs in a class << self nested two
  # levels down are singleton subjects of the inner class.
  it "finds singleton-class subjects at nesting depth >= 2" do
    expect(ids("class A\n  class B\n    class << self\n      def deep; end\n    end\n  end\nend\n"))
      .to eq(["A::B.deep"])
  end

  # The `last` -> `first` guard mutant: a class << self nested inside a
  # class << self attaches nowhere the finder can name, so it defines no
  # subjects.
  it "skips a class << self nested inside a class << self" do
    expect(ids("class A\n  class << self\n    class << self\n      def deep; end\n    end\n  end\nend\n")).to eq([])
  end

  # e4401d8be317a763: dropping the nesting.empty? side calls sclass? on
  # nil for a top-level class << self.
  it "skips a top-level class << self with no enclosing scope" do
    expect(ids("class << self\n  def m; end\nend\n")).to eq([])
  end

  # `class << obj` (non-self expression) bodies are not subjects.
  it "skips class << obj bodies" do
    expect(ids("class A\n  class << B\n    def m; end\n  end\nend\n")).to eq([])
  end

  # frozen_literals? comment parsing (08f02137f2484b48 family): a dashed
  # key normalizes like the underscored one.
  it "notes a dashed frozen-string-literal magic comment" do
    expect(subjects_in("# frozen-string-literal: true\nclass A\n  def m; end\nend\n").first.frozen_literals).to be(true)
  end

  # 08f02137f2484b48: dropping the key check reads any true-valued magic
  # comment as frozen_string_literal.
  it "does not read an unrelated magic comment's true value as frozen_string_literal" do
    expect(subjects_in("# typed: true\nclass A\n  def m; end\nend\n").first.frozen_literals).to be(false)
  end

  # The define_method_subject? guards: name, bare receiver, argument
  # presence and literal-name shape each decide alone.
  it "rejects define_method lookalikes and keeps the real shape" do
    finder = described_class.new
    node = ->(source) { Prism.parse(source).value.statements.body.first }
    expect(finder.send(:define_method_subject?, node.call("foo(:x) { 1 }"))).to be(false)
    expect(finder.send(:define_method_subject?, node.call("obj.define_method(:x) { 1 }"))).to be(false)
    expect(finder.send(:define_method_subject?, node.call("define_method { 1 }"))).to be(false)
    expect(finder.send(:define_method_subject?, node.call("define_method(1) { 2 }"))).to be(false)
    expect(finder.send(:define_method_subject?, node.call("define_method(:x) { 1 }"))).to be(true)
    expect(finder.send(:define_method_subject?, node.call('define_method("x") { 1 }'))).to be(true)
  end

  # Only one side of the && holds: right key, false value; right value,
  # wrong key.
  it "ignores a frozen_string_literal comment whose value is not true, and a true comment with another key" do
    literals = subjects_in("# frozen_string_literal: false\nclass A\n  def m; end\nend\n")
    expect(literals.first.frozen_literals).to be(false)
    expect(subjects_in("# frozen_string_literal: yes\nclass A\n  def m; end\nend\n").first.frozen_literals).to be(false)
  end

  # #627: `def Const.m` defines a singleton on the named constant, which the
  # enclosing owner cannot re-evaluate - and it used to vanish silently, so
  # `run --all` read as "nothing to mutate" when the file was full of defs.
  # Report-it-or-support-it: emit a skipped subject the report names.
  it "reports constant-receiver defs as skipped subjects instead of dropping them (#627)" do
    found = subjects_in(<<~RUBY)
      class K
        def K.b; 2; end
        def self.c; 3; end
        def d; 4; end
      end
    RUBY
    expect(found.map { |subject| [subject.id, subject.skip_reason] })
      .to eq([["K.b", "constant-receiver def"], ["K.c", nil], ["K#d", nil]])
    skipped = found.first
    expect([skipped.name, skipped.owner, skipped.singleton, skipped.sclass]).to eq([:b, "K", true, false])
  end

  it "still drops receivers saboteur cannot name, like a local (#627)" do
    found = subjects_in("class K\n  def build\n    k = K.new\n    def k.m; 1; end\n  end\nend\n")
    expect(found.map(&:id)).to eq(["K#build"])
  end
end
