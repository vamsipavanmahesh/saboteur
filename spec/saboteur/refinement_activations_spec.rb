# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::RefinementActivations do
  # A minimal subject stand-in: mark only reads start_byte and writes
  # skip_reason.
  def stub_at(source, marker)
    Struct.new(:start_byte, :skip_reason).new(source.index(marker), nil)
  end

  def mark(source, *markers)
    subjects = markers.map { |marker| stub_at(source, marker) }
    described_class.mark(subjects, Prism.parse(source).value)
    subjects.map(&:skip_reason)
  end

  it "covers a def after a class-body using, including a def self.m" do
    source = "class A\n  using M\n  def m; 1; end\n  def self.s; 2; end\nend\n"
    expect(mark(source, "def m", "def self.s")).to eq(%w[refinements refinements])
  end

  it "leaves a def before the using and a def in a sibling scope unskipped" do
    source = "module A\n  def before; 1; end\n  using M\nend\nmodule B\n  def b_m; 2; end\nend\n"
    expect(mark(source, "def before", "def b_m")).to eq([nil, nil])
  end

  it "covers a nested class body after the using, but not a reopened body" do
    source = "module A\n  using M\n  class B\n    def m; 1; end\n  end\nend\nmodule A\n  def reopened; 2; end\nend\n"
    expect(mark(source, "def m", "def reopened")).to eq(["refinements", nil])
  end

  # any?, not all?: one covering site is enough, a non-covering second
  # site does not cancel it.
  it "skips when any site covers the subject, not only when all do" do
    source = "module A\n  using First\nend\nmodule B\n  using Second\n  def m; 1; end\nend\n"
    expect(mark(source, "def m")).to eq(["refinements"])
  end

  it "records a using in a superclass expression as a site of the enclosing scope" do
    source = "class A < (using M; Object)\nend\nclass B\n  def m; 1; end\nend\n"
    expect(mark(source, "def m")).to eq(["refinements"])
  end

  it "ignores a using with a receiver" do
    source = "class A\n  x.using(M)\n  def m; 1; end\nend\n"
    expect(mark(source, "def m")).to eq([nil])
  end

  it "scopes a using inside class << self to that body only" do
    source = "class A\n  class << self\n    using M\n    def s; 1; end\n  end\n  def m; 2; end\nend\n"
    expect(mark(source, "def s", "def m")).to eq(["refinements", nil])
  end

  it "keeps the whole-file skip when a def body and a scope body both carry a using" do
    source = "module A\n  def a_m; using M; end\nend\n" \
             "module B\n  using N\n  def b_m; 1; end\nend\n" \
             "module C\n  def c_m; 2; end\nend\n"
    expect(mark(source, "def a_m", "def b_m", "def c_m")).to eq(["refinements"] * 3)
  end

  # A dynamic site never reaches covers? through mark (the whole-file
  # branch returns first); pinned directly so the guard stays honest.
  it "never covers through a dynamic site" do
    site = described_class::Site.new(start_byte: 0, scope_end: 100, dynamic_scope: true)
    expect(site.covers?(stub_at("x = 1\ndef m; 1; end\n", "def m"))).to be(false)
  end

  # Empty scope bodies are nil in Prism: the body guards in descend must
  # stay, or a `module E; end` after a using crashes the walk.
  it "tolerates empty scope bodies after a using" do
    source = "module A\n  using M\n  def a_m; 1; end\nend\n" \
             "module E; end\nclass F; end\n"
    expect(mark(source, "def a_m")).to eq(["refinements"])
  end
end
