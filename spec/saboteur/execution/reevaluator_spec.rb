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

    it "keeps the file's own name and line numbers" do
      described_class.new("nesting", whole_file: ["WholeFileThing#value"])
                     .call(subject_under_test, subject_under_test.source.sub("1", "10"))
      file, line = WholeFileThing.instance_method(:value).source_location
      expect([file, line]).to eq([subject_under_test.file, subject_under_test.start_line])
    end
  end
end
