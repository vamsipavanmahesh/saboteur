# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Execution::Reevaluator, "same-line defs, inherit flags and Kernel constants" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    ensure
      Object.send(:remove_const, :PinRe) if Object.const_defined?(:PinRe, false)
      Kernel.send(:remove_const, :PinKH) if Kernel.const_defined?(:PinKH, false)
    end
  end

  def load_subjects(code)
    @path = File.join(@dir, "pin_re3.rb")
    File.write(@path, code)
    load @path
    Saboteur::SubjectFinder.new.call(@path).subjects.to_h { |s| [s.id, s] }
  end

  def mutate(subject, from, to, strategy)
    described_class.new(strategy).call(subject, subject.source.sub(from, to))
  end

  %w[nesting class_eval].each do |strategy|
    context "with #{strategy}" do
      it "does not repoint another method defined on the same line" do
        subject = load_subjects("class PinRe\n  def one = 1; def two = 2\nend\n").fetch("PinRe#one")
        mutate(subject, "1", "5", strategy)
        expect(PinRe.new.one).to eq(5)
        expect(PinRe.new.two).to eq(2)
      end

      it "makes no singleton copy for a private method of an extend self module" do
        subject = load_subjects("module PinRe\n  extend self\n  private def helper = 1\nend\n").fetch("PinRe#helper")
        mutate(subject, "1", "2", strategy)
        expect(PinRe.private_method_defined?(:helper)).to be(true)
        expect(PinRe.singleton_class.private_method_defined?(:helper, false)).to be(false)
        expect(PinRe.singleton_class.method_defined?(:helper, false)).to be(false)
      end

      %w[private protected].each do |kind|
        it "keeps a public method public when a prepended module has a #{kind} one of that name" do
          code = "module PinReHidden\n  #{kind} def foo = 9\nend\n" \
                 "class PinRe\n  prepend PinReHidden\n  def foo = 2\nend\n"
          subject = load_subjects(code).fetch("PinRe#foo")
          mutate(subject, "2", "3", strategy)
          expect(PinRe.public_method_defined?(:foo, false)).to be(true)
        ensure
          Object.send(:remove_const, :PinReHidden) if Object.const_defined?(:PinReHidden, false)
        end
      end
    end
  end

  it "does not find a head constant that only Kernel defines" do
    Kernel.const_set(:PinKH, Module.new { const_set(:Leaf, Class.new) })
    path = File.join(@dir, "pin_kh.rb")
    File.write(path, "class PinKH::Leaf\n  def m = 1\nend\n")
    subject = Saboteur::SubjectFinder.new.call(path).subjects.find { |s| s.id == "PinKH::Leaf#m" }
    expect { described_class.new.resolve_owner(subject) }
      .to raise_error(Saboteur::Error, /\Acannot resolve PinKH::Leaf: /)
  end
end
