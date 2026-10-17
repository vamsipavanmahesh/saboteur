# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::Reevaluator do
  fixture = File.expand_path("../../fixtures/ruby/reeval_targets.rb", __dir__)

  let(:subjects) { Saboteur::SubjectFinder.new.call(fixture).subjects.to_h { |s| [s.id, s] } }
  let(:person) { ReevalTargets::Person }

  before do
    # Reload so every example starts from the original definitions.
    Object.send(:remove_const, :ReevalTargets) if defined?(ReevalTargets)
    load fixture
  end

  def reeval(id, strategy, from: nil, to: nil)
    subject = subjects.fetch(id)
    text = from ? subject.source.sub(from, to) : subject.source
    described_class.new(strategy).call(subject, text)
  end

  described_class::STRATEGIES.each do |strategy|
    context "with #{strategy}" do
      it "keeps a private method private" do
        reeval("ReevalTargets::Person#secret", strategy, from: ":secret", to: ":mutated")
        expect(person.private_method_defined?(:secret)).to be(true)
        expect(person.new(1).call_secret).to eq(:mutated)
      end

      it "keeps a protected method protected" do
        reeval("ReevalTargets::Person#guarded", strategy, from: ":guarded", to: ":mutated")
        expect(person.protected_method_defined?(:guarded)).to be(true)
        expect(person.new(1).compare(person.new(2))).to eq(:mutated)
      end

      it "leaves a public method public" do
        reeval("ReevalTargets::Person#greeting", strategy)
        expect(person.public_method_defined?(:greeting)).to be(true)
      end

      it "redefines a define_method body on the class (#194)" do
        reeval("ReevalTargets::Person#dm_doubled", strategy, from: "n * 2", to: "n * 3")
        expect(person.new(1).dm_doubled(2)).to eq(6)
      end

      it "redefines def self.x on the class" do
        reeval("ReevalTargets::Person.make", strategy, from: "new(age)", to: ":mutated")
        expect(person.make(1)).to eq(:mutated)
      end

      it "redefines methods from class << self, keeping private ones private" do
        reeval("ReevalTargets::Person.factory", strategy, from: ":factory", to: ":mutated")
        reeval("ReevalTargets::Person.hidden_factory", strategy, from: ":hidden", to: ":mutated")
        expect(person.factory).to eq(:mutated)
        expect(person.singleton_class.private_method_defined?(:hidden_factory)).to be(true)
        expect(person.send(:hidden_factory)).to eq(:mutated)
      end

      it "re-applies module_function to both copies" do
        reeval("ReevalTargets::Util#twice", strategy, from: "value * 2", to: "value * 3")
        expect(ReevalTargets::Util.twice(2)).to eq(6)
        expect(ReevalTargets::Util.private_method_defined?(:twice)).to be(true)
      end

      it "re-applies private and protected module-function copies without exposing them" do
        reeval("ReevalTargets::PrivateCopies#hidden", strategy, from: ":original", to: ":mutated")
        reeval("ReevalTargets::PrivateCopies#protected_copy", strategy, from: ":original", to: ":mutated")
        copies = ReevalTargets::PrivateCopies
        expect(copies.public_contract).to eq(%i[mutated mutated])
        expect(copies.singleton_class.private_method_defined?(:hidden, false)).to be(true)
        expect(copies.singleton_class.protected_method_defined?(:protected_copy, false)).to be(true)
        expect(copies.private_method_defined?(:hidden, false)).to be(true)
        expect(copies.private_method_defined?(:protected_copy, false)).to be(true)
      end

      it "re-points aliases at the mutated method, keeping their visibility" do
        reeval("ReevalTargets::Priced#total", strategy, from: "10", to: "11")
        reeval("ReevalTargets::Priced#secret_total", strategy, from: "1", to: "2")
        priced = ReevalTargets::Priced.new
        expect([priced.total, priced.sum, priced.amount]).to eq([11, 11, 11])
        expect(priced.send(:hidden_sum)).to eq(2)
        expect(ReevalTargets::Priced.private_method_defined?(:hidden_sum)).to be(true)
      end

      it "leaves alone an alias of an older definition of the same name" do
        reeval("ReevalTargets::Redefined#total", strategy, from: "20", to: "21")
        expect([ReevalTargets::Redefined.new.total, ReevalTargets::Redefined.new.original_total]).to eq([21, 10])
      end

      it "keeps the original file and line for backtraces" do
        reeval("ReevalTargets::Person#greeting", strategy)
        expect(person.instance_method(:greeting).source_location).to eq([fixture, 16])
      end

      it "keeps frozen string literals from the magic comment" do
        reeval("ReevalTargets::Person#greeting", strategy)
        expect(person.new(1).greeting).to be_frozen
      end

      it "redefines a method on a Data.define class without touching the class (#290)" do
        point_class = ReevalTargets::Point
        reeval("ReevalTargets::Point#doubled", strategy, from: "x * 2", to: "x * 3")
        expect(ReevalTargets::Point).to be(point_class)
        expect(ReevalTargets::Point.members).to eq([:x])
        expect(ReevalTargets::Point.new(2).doubled).to eq(6)
      end

      it "redefines a method on a Struct.new class without touching the class (#290)" do
        pair_class = ReevalTargets::Pair
        reeval("ReevalTargets::Pair#total", strategy, from: "a + b", to: "a * b")
        expect(ReevalTargets::Pair).to be(pair_class)
        expect(ReevalTargets::Pair.new(2, 3).total).to eq(6)
      end

      it "redefines a method on a Module.new module without touching it (#290)" do
        tools = ReevalTargets::Tools
        reeval("ReevalTargets::Tools.version", strategy, from: "1", to: "2")
        expect(ReevalTargets::Tools).to be(tools)
        expect(ReevalTargets::Tools.version).to eq(2)
      end

      it "redefines a factory class assigned inside class << self, on the same class (#352)" do
        widget_class = ReevalTargets::Host.singleton_class::Widget
        reeval("ReevalTargets::Host::Widget#doubled", strategy, from: "count * 2", to: "count * 3")
        expect(ReevalTargets::Host.singleton_class::Widget).to be(widget_class)
        expect(ReevalTargets::Host.singleton_class::Widget.new(2).doubled).to eq(6)
      end
    end
  end

  describe "constant lookup (design 6.1)" do
    it "loses constants from enclosing modules with class_eval" do
      reeval("ReevalTargets::Person#adult?", "class_eval")
      expect { person.new(20).adult? }.to raise_error(NameError, /LIMIT/)
    end

    it "keeps them with the nesting strategy" do
      reeval("ReevalTargets::Person#adult?", "nesting")
      expect(person.new(20).adult?).to be(true)
    end

    it "keeps them for factory classes through the class_eval wrapper (#290)" do
      reeval("ReevalTargets::Outer::Meter#scaled", "nesting", from: "n * SCALE", to: "n * SCALE + 1")
      expect(ReevalTargets::Outer::Meter.new(2).scaled).to eq(21)
    end

    it "resolves a factory nested in a factory block by its lexical owner (#339)" do
      coin_class = ReevalTargets::Coin
      reeval("ReevalTargets::Coin#doubled", "nesting", from: "cents * 2", to: "cents * 3")
      expect(ReevalTargets::Coin).to be(coin_class)
      expect(ReevalTargets::Coin.members).to eq([:cents])
      expect(ReevalTargets::Coin.new(2).doubled).to eq(6)
      expect(ReevalTargets::Bag).not_to be_const_defined(:Coin, false)
    end
  end

  it "uses the nesting strategy by default (maintainer decision M1)" do
    subject = Saboteur::SubjectFinder.new.call(fixture).subjects.find { |s| s.id == "ReevalTargets::Person#adult?" }
    described_class.new.call(subject, subject.source)
    expect(ReevalTargets::Person.new(20).adult?).to be(true)
  end

  it "rejects unknown strategies" do
    expect { described_class.new("instance_eval") }.to raise_error(Saboteur::Error, /unknown reeval/)
  end

  it "raises a saboteur error when the owner is not defined" do
    subject = subjects_in("module Nowhere\n  class Missing\n    def x; end\n  end\nend\n").first
    expect { described_class.new.call(subject, subject.source) }.to raise_error(Saboteur::Error, /cannot resolve/)
  end

  it "evaluates a prefix at the lines above the def, keeping the def at its original line" do
    subject = subject_named("class PrefixTarget\n  def m\n    1\n  end\nend\n", "PrefixTarget#m")
    load subject.file
    described_class.new.call(subject, subject.source,
                             prefix: "PrefixTarget.instance_variable_set(:@prefix_line, __LINE__)")
    expect(PrefixTarget.instance_variable_get(:@prefix_line)).to eq(subject.start_line - 1)
    expect(PrefixTarget.instance_method(:m).source_location).to eq([subject.file, subject.start_line])
  end

  describe "whole_file" do
    let(:source) do
      <<~RUBY
        WHOLE_FILE_LOADS = (defined?(WHOLE_FILE_LOADS) ? WHOLE_FILE_LOADS : 0) + 1

        class WholeFileThing
          def value
            1
          end

          def other
            2
          end
        end
      RUBY
    end
    let(:subject_under_test) do
      subjects_in(source, name: "whole_file_thing.rb").find do |s|
        s.id == "WholeFileThing#value"
      end
    end

    before do
      Object.send(:remove_const, :WHOLE_FILE_LOADS) if defined?(WHOLE_FILE_LOADS)
      Object.send(:remove_const, :WholeFileThing) if defined?(WholeFileThing)
      load subject_under_test.file
    end

    after do
      Object.send(:remove_const, :WHOLE_FILE_LOADS) if defined?(WHOLE_FILE_LOADS)
      Object.send(:remove_const, :OUTSIDE_GREETING) if defined?(OUTSIDE_GREETING)
      Object.send(:remove_const, :WholeFileThing) if defined?(WholeFileThing)
    end

    it "matches subject ids exactly or by glob" do
      expect(described_class.new("nesting",
                                 whole_file: ["WholeFileThing#value"]).whole_file?(subject_under_test)).to be(true)
      expect(described_class.new("nesting", whole_file: ["WholeFile*"]).whole_file?(subject_under_test)).to be(true)
      expect(described_class.new("nesting", whole_file: ["Other#value"]).whole_file?(subject_under_test)).to be(false)
      expect(described_class.new.whole_file?(subject_under_test)).to be(false)
    end

    it "evaluates the whole file with the mutated method spliced in, running its top-level code again" do
      reevaluator = described_class.new("nesting", whole_file: ["WholeFileThing#value"])
      reevaluator.call(subject_under_test, subject_under_test.source.sub("1", "10"))
      expect(WholeFileThing.new.value).to eq(10)
      expect(WholeFileThing.new.other).to eq(2)
      expect(WHOLE_FILE_LOADS).to eq(2)
    end

    it "leaves methods outside the list to surgical re-evaluation" do
      reevaluator = described_class.new("nesting", whole_file: ["Nothing#here"])
      reevaluator.call(subject_under_test, subject_under_test.source.sub("1", "10"))
      expect(WholeFileThing.new.value).to eq(10)
      expect(WHOLE_FILE_LOADS).to eq(1)
    end

    it "reports no replaced definition while the subject's own def is the one in place" do
      reevaluator = described_class.new("nesting", whole_file: ["WholeFileThing#value"])
      reevaluator.call(subject_under_test, subject_under_test.source.sub("1", "10"))
      expect(reevaluator.replaced_definition(subject_under_test)).to be_nil
    end

    it "reports no replaced definition for a subject that is not whole-file" do
      expect(described_class.new.replaced_definition(subject_under_test)).to be_nil
    end

    it "names the definition that replaced it when a later def in the file wins" do
      twice = "class WholeFileThing\n  def value\n    1\n  end\n\n  def value\n    2\n  end\nend\n"
      first = subjects_in(twice, name: "whole_file_twice.rb").find { |s| s.id == "WholeFileThing#value" }
      reevaluator = described_class.new("nesting", whole_file: ["WholeFileThing#value"])
      reevaluator.call(first, first.source.sub("1", "10"))
      expect(WholeFileThing.new.value).to eq(2)
      expect(reevaluator.replaced_definition(first)).to eq("#{first.file}:6")
    end

    it "looks through a known def-time wrapper to the def it wraps" do
      reevaluator = described_class.new("nesting", whole_file: ["WholeFileThing#value"])
      reevaluator.call(subject_under_test, subject_under_test.source.sub("1", "10"))
      wrapped = instance_double(UnboundMethod, source_location: ["/gems/sorbet/wrapper.rb", 1])
      original = instance_double(UnboundMethod,
                                 source_location: [subject_under_test.file, subject_under_test.start_line])
      allow(Saboteur::Execution::Wrapper).to receive(:original_def).with(wrapped).and_return(original)
      allow(WholeFileThing).to receive(:instance_method).with(:value).and_return(wrapped)
      expect(reevaluator.replaced_definition(subject_under_test)).to be_nil
    end

    it "keeps the verdict for an unknown wrapper: a def from another file is not a replacement" do
      reevaluator = described_class.new("nesting", whole_file: ["WholeFileThing#value"])
      forwarding = instance_double(UnboundMethod, source_location: ["/gems/forwarder.rb", 3])
      allow(Saboteur::Execution::Wrapper).to receive(:original_def).with(forwarding).and_return(nil)
      allow(WholeFileThing).to receive(:instance_method).with(:value).and_return(forwarding)
      expect(reevaluator.replaced_definition(subject_under_test)).to be_nil
    end

    it "reports a wrapped method whose wrapped def is another def in the subject's file" do
      reevaluator = described_class.new("nesting", whole_file: ["WholeFileThing#value"])
      wrapped = instance_double(UnboundMethod,
                                source_location: [subject_under_test.file, subject_under_test.start_line])
      original = instance_double(UnboundMethod, source_location: [subject_under_test.file, 9])
      allow(Saboteur::Execution::Wrapper).to receive(:original_def).with(wrapped).and_return(original)
      allow(WholeFileThing).to receive(:instance_method).with(:value).and_return(wrapped)
      expect(reevaluator.replaced_definition(subject_under_test)).to eq("#{subject_under_test.file}:9")
    end

    it "keeps the verdict for a method that is no longer defined" do
      reevaluator = described_class.new("nesting", whole_file: ["WholeFileThing#value"])
      WholeFileThing.send(:remove_method, :value)
      expect(reevaluator.replaced_definition(subject_under_test)).to be_nil
    end

    it "keeps the verdict for a definition with no Ruby source, such as a native method" do
      native = Struct.new(:id, :singleton, :name, :file, :start_line).new("String#size", false, :size, "x.rb", 1)
      reevaluator = described_class.new("nesting", whole_file: ["String#size"])
      allow(reevaluator).to receive(:resolve_owner).and_return(String)
      expect(reevaluator.replaced_definition(native)).to be_nil
    end

    it "keeps non-ASCII text inside and outside the method as UTF-8 even when the file was read as binary" do
      source = "# frozen_string_literal: true\n\nOUTSIDE_GREETING = \"h\u00e9llo\"\n\nclass WholeFileThing\n  " \
               "def value\n    \"caf\u00e9\"\n  end\nend\n"
      thing = subjects_in(source, name: "whole_file_utf8.rb").find { |s| s.id == "WholeFileThing#value" }
      allow(thing).to receive(:file_source).and_return(source.b)
      reevaluator = described_class.new("nesting", whole_file: ["WholeFileThing#value"])
      reevaluator.call(thing, "def value\n    \"caf\u00e9!\"\n  end")
      expect(WholeFileThing.new.value).to eq("caf\u00e9!")
      expect([WholeFileThing.new.value.encoding, OUTSIDE_GREETING.encoding]).to eq([Encoding::UTF_8] * 2)
    end

    it "keeps the file's own name and line numbers" do
      described_class.new("nesting", whole_file: ["WholeFileThing#value"])
                     .call(subject_under_test, subject_under_test.source.sub("1", "10"))
      file, line = WholeFileThing.instance_method(:value).source_location
      expect([file, line]).to eq([subject_under_test.file, subject_under_test.start_line])
    end
  end
end

RSpec.describe Saboteur::Execution::Reevaluator, "whole_file_only? subjects (issue #306)" do
  it "evaluates a whole_file_only? subject as a whole file even without a whole_file entry" do
    subject = subjects_in("class K\n  def m = 1\nend\n").first
    allow(subject).to receive(:whole_file_only?).and_return(true)
    expect(described_class.new.whole_file?(subject)).to be(true)
  end
end
