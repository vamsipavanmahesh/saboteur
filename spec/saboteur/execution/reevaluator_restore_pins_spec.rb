# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Execution::Reevaluator, "restore and placement" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    ensure
      %i[PinRe PinHead].each { |name| Object.send(:remove_const, name) if Object.const_defined?(name, false) }
    end
  end

  def load_subjects(code)
    @path = File.join(@dir, "pin_re.rb")
    File.write(@path, code)
    load @path
    Saboteur::SubjectFinder.new.call(@path).subjects.to_h { |s| [s.id, s] }
  end

  def mutate(subject, from, to, strategy: "nesting", prefix: nil, whole_file: [])
    described_class.new(strategy, whole_file: whole_file).call(subject, subject.source.sub(from, to), prefix: prefix)
  end

  %w[nesting class_eval].each do |strategy|
    context "with #{strategy}" do
      it "keeps a public module_function-style method public beside its singleton copy" do
        code = "module PinRe\n  def foo = 1\n  module_function :foo\n  public :foo\nend\n"
        subject = load_subjects(code).fetch("PinRe#foo")
        mutate(subject, "1", "2", strategy: strategy)
        expect(PinRe.public_method_defined?(:foo)).to be(true)
      end

      it "re-applies a private instance method of a module that has no singleton copy" do
        subject = load_subjects("module PinRe\n  private def foo = 1\nend\n").fetch("PinRe#foo")
        mutate(subject, "1", "2", strategy: strategy)
        expect(PinRe.private_method_defined?(:foo)).to be(true)
        expect(PinRe.singleton_class.method_defined?(:foo, false)).to be(false)
      end

      it "leaves a separately defined singleton method of the same name alone" do
        code = "module PinRe\n  def self.foo = :single\n  private def foo = 1\nend\n"
        subject = load_subjects(code).fetch("PinRe#foo")
        mutate(subject, "1", "2", strategy: strategy)
        expect(PinRe.foo).to eq(:single)
        expect(PinRe.private_method_defined?(:foo)).to be(true)
      end

      it "repoints a private alias of the current definition and keeps it private" do
        code = "class PinRe\n  def foo = 1\n  alias_method :hidden, :foo\n  private :hidden\nend\n"
        subject = load_subjects(code).fetch("PinRe#foo")
        mutate(subject, "1", "3", strategy: strategy)
        expect(PinRe.private_method_defined?(:hidden)).to be(true)
        expect(PinRe.new.send(:hidden)).to eq(3)
      end

      it "does not repoint an alias taken before the method was redefined" do
        code = "class PinRe\n  def foo = 1\n  alias_method :old, :foo\n  def foo = 2\nend\n"
        subject = load_subjects(code).fetch("PinRe#foo")
        mutate(subject, "2", "3", strategy: strategy)
        expect(PinRe.new.foo).to eq(3)
        expect(PinRe.new.old).to eq(1)
      end
    end
  end

  it "keeps the def on its file line, with and without a frozen_string_literal comment and a prefix" do
    plain = load_subjects("class PinRe\n\n  def foo = \"lit\".frozen?\nend\n").fetch("PinRe#foo")
    mutate(plain, "frozen?", "frozen?")
    expect(PinRe.instance_method(:foo).source_location).to eq([@path, 3])
    expect(PinRe.new.foo).to be(false)
    mutate(plain, "\"lit\".frozen?", ":x", prefix: "nil")
    expect(PinRe.instance_method(:foo).source_location).to eq([@path, 3])
    expect(PinRe.new.foo).to eq(:x)
    mutate(plain, "\"lit\".frozen?", ":y", prefix: "nil\nnil")
    expect(PinRe.instance_method(:foo).source_location).to eq([@path, 3])
    expect(PinRe.new.foo).to eq(:y)
    Object.send(:remove_const, :PinRe)
    code = "# frozen_string_literal: true\n\nclass PinRe\n  def foo = \"lit\".frozen?\nend\n"
    frozen = load_subjects(code).fetch("PinRe#foo")
    mutate(frozen, "frozen?", "frozen?")
    expect(PinRe.instance_method(:foo).source_location).to eq([@path, 4])
    expect(PinRe.new.foo).to be(true)
    mutate(frozen, "frozen?", "frozen?", prefix: "nil\nnil")
    expect(PinRe.instance_method(:foo).source_location).to eq([@path, 4])
  end

  it "does not leak warnings and restores $VERBOSE" do
    subject = load_subjects("class PinRe\n  def foo = 1\nend\n").fetch("PinRe#foo")
    warnings = []
    original = $VERBOSE
    $VERBOSE = true
    allow(Warning).to receive(:warn) { |message, **| warnings << message }
    mutate(subject, "1", "2")
    expect($VERBOSE).to be(true)
    expect(warnings).to eq([])
  ensure
    $VERBOSE = original
  end

  it "reports a later def in the same file as a replacement, only for whole-file subjects" do
    code = "class PinRe\n  def foo = 1\n  def foo = 2\n  def self.bar = 1\n  def self.bar = 2\nend\n"
    load_subjects(code)
    subjects = Saboteur::SubjectFinder.new.call(@path).subjects
    first = subjects.find { |s| s.id == "PinRe#foo" && s.start_line == 2 }
    expect(described_class.new.replaced_definition(first)).to be_nil
    expect(described_class.new("nesting", whole_file: ["*"]).replaced_definition(first)).to eq("#{@path}:3")
    single = subjects.find { |s| s.id == "PinRe.bar" && s.start_line == 4 }
    expect(described_class.new("nesting", whole_file: ["*"]).replaced_definition(single)).to eq("#{@path}:5")
  end

  it "finds a dotted head in an outer scope even when a top-level constant shares its name" do
    Object.class_eval("module PinHead; class Leaf; end; end; module PinRe; module PinHead; class Leaf; end; end; " \
                      "module Inner; end; end", __FILE__, __LINE__ - 1)
    code = "module PinRe\n  module Inner\n    class PinHead::Leaf\n      def m = 1\n    end\n  end\nend\n"
    path = File.join(@dir, "pin_head.rb")
    File.write(path, code)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.find { |s| s.id == "PinRe::Inner::PinHead::Leaf#m" }
    expect(described_class.new.resolve_owner(subject)).to equal(PinRe::PinHead::Leaf)
  end

  it "refuses an unknown strategy by name" do
    expect { described_class.new("bogus") }.to raise_error(Saboteur::Error, "unknown reeval strategy: bogus")
    expect { described_class.new(:class_eval) }.not_to raise_error
  end

  it "evaluates a whole file from a frozen source string" do
    subject = load_subjects("class PinRe\n  def foo = 1\nend\n").fetch("PinRe#foo")
    allow(subject).to receive(:file_source).and_return(File.read(@path).freeze)
    described_class.new("nesting", whole_file: ["*"]).call(subject, subject.source.sub("1", "5"))
    expect(PinRe.new.foo).to eq(5)
  end
end
