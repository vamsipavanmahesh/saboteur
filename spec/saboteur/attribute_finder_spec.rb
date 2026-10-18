# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::AttributeFinder do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def find(text)
    file = File.join(@root, "sample.rb")
    File.write(file, text)
    Saboteur::AttributeFinder.new.call(file)
  end

  it "finds attr_reader, attr_writer and attr_accessor methods with their owner" do
    found = find("module Shop\n  class Cart\n    attr_reader :name\n    attr_writer :price\n    " \
                 "attr_accessor :note\n  end\nend\n")
    expect(found.map(&:id)).to eq(["Shop::Cart#name", "Shop::Cart#price=", "Shop::Cart#note", "Shop::Cart#note="])
    expect(found.map(&:macro)).to eq(%i[attr_reader attr_writer attr_accessor attr_accessor])
  end

  it "accepts string names and several names in one call" do
    found = find("class Cart\n  attr_reader 'a', :b\nend\n")
    expect(found.map(&:id)).to eq(["Cart#a", "Cart#b"])
  end

  it "names attribute methods inside class << self as singletons" do
    found = find("class Cart\n  class << self\n    attr_reader :registry\n  end\nend\n")
    expect(found.map(&:id)).to eq(["Cart.registry"])
  end

  it "restarts the owner path at a rooted class name" do
    found = find("module Outer\n  class ::Cart\n    attr_reader :name\n  end\nend\n")
    expect(found.map(&:id)).to eq(["Cart#name"])
  end

  it "finds a macro nested under a visibility call" do
    found = find("class Cart\n  private attr_reader :name\nend\n")
    expect(found.map(&:id)).to eq(["Cart#name"])
  end

  it "skips macros inside blocks: the runtime self is unknowable" do
    found = find("class Cart\n  included do\n    attr_reader :name\n  end\nend\n")
    expect(found).to be_empty
  end

  it "finds nothing in a file that does not parse" do
    expect(find("def nope(\n")).to eq([])
  end

  it "finds no owner at the top level" do
    expect(find("attr_reader :name\n")).to eq([])
  end

  # A receivered call (Foo.attr_reader) or a macro handed a block is not
  # the plain macro: say nothing rather than guess (#373 dogfood).
  it "ignores a macro with a receiver or a block" do
    expect(find("class Cart\n  Foo.attr_reader :x\nend\n")).to eq([])
    expect(find("class Cart\n  attr_reader(:x) { 1 }\nend\n")).to eq([])
  end

  # `class << self` names a singleton only inside a named class or module:
  # at the top level, or nested inside another `class << self`, the macro
  # attaches somewhere the finder cannot name, so it stays silent.
  it "ignores a macro in a top-level class << self" do
    expect(find("class << self\n  attr_reader :x\nend\n")).to eq([])
  end

  it "ignores a macro in a class << self nested inside class << self" do
    expect(find("class C\n  class << self\n    class << self\n      attr_reader :x\n    end\n  end\nend\n"))
      .to eq([])
  end

  it "ignores a macro in the singleton class of an explicit object" do
    expect(find("class C\n  x = new\n  class << x\n    attr_reader :y\n  end\nend\n")).to eq([])
  end

  # A parse failure anywhere means no attribute claims at all - even for a
  # macro before the error: the finder never reports half a file.
  it "finds nothing when a macro sits before the syntax error" do
    expect(find("class C\n  attr_reader :x\ndef nope(\n")).to eq([])
  end

  # A computed macro name (a constant, a call) says nothing; the literal
  # names in the same call still count.
  it "skips a non-literal macro argument but keeps the literal ones" do
    found = find("class Cart\n  attr_reader :a, SOME_CONST, :b\nend\n")
    expect(found.map(&:id)).to eq(["Cart#a", "Cart#b"])
  end

  it "ignores a macro with no arguments" do
    expect(find("class Cart\n  attr_reader\nend\n")).to eq([])
  end

  it "keeps a compact class path as the owner" do
    found = find("class A::B\n  attr_reader :x\nend\n")
    expect(found.map(&:id)).to eq(["A::B#x"])
  end

  # Walking a class with no body hands walk a nil node: the guard keeps
  # the walk alive for the sibling that follows.
  it "finds macros after an empty class body" do
    found = find("class C\nend\nclass D\n  attr_reader :x\nend\n")
    expect(found.map(&:id)).to eq(["D#x"])
  end

  # Entering a module adds to the nesting; it never drops an enclosing
  # class (dogfood: operand_replacement on the module branch).
  it "nests a module inside an enclosing class" do
    found = find("class Outer\n  module M\n    attr_reader :x\n  end\nend\n")
    expect(found.map(&:id)).to eq(["Outer::M#x"])
  end

  # The in_block flag flows through a wrapping call: a macro nested as a
  # call argument inside a block still binds to an unknowable self.
  it "ignores a macro nested in a call inside a block" do
    expect(find("class C\n  included do\n    foo(attr_reader :x)\n  end\nend\n")).to eq([])
  end

  # A receiverless call that is no macro defines nothing (dogfood: each
  # side of the record_macro guard alone decides).
  it "ignores a receiverless call that is no macro" do
    expect(find("class C\n  foo :x\nend\n")).to eq([])
  end

  # The filepath kwarg labels parse diagnostics; pin it so it is never
  # dropped as dead text (dogfood: pair_removal on Prism.parse).
  it "parses with the file path for diagnostics" do
    file = File.join(@root, "sample.rb")
    File.write(file, "class C\n  attr_reader :x\nend\n")
    allow(Prism).to receive(:parse).and_call_original
    Saboteur::AttributeFinder.new.call(file)
    expect(Prism).to have_received(:parse).with(anything, filepath: file)
  end
  it "refuses a file nested deeper than the walker can safely recurse (#719)" do
    expect { find("#{'a(' * 1500}1#{')' * 1500}\n") }.to raise_error(Saboteur::DeepSourceError, /sample\.rb/)
  end
end
