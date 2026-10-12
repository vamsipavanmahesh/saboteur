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

  it "skips top-level defs, nested defs, defs in blocks and def obj.x" do
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
    expect(ids(source)).to eq(["A#outer"])
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
end
