# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::DeclaredReturn do
  def subject_with_sig(sig, body: "    work\n    value")
    source = "class DeclaredReturnProbe\n  #{sig}\n  def m(a)\n#{body}\n  end\nend\n"
    subjects_in(source).first
  end

  def excludes_nil?(sig)
    described_class.new(subject_with_sig(sig)).excludes_nil?
  end

  it "is true for a class that nil is not an instance of" do
    expect(excludes_nil?("sig { params(a: Integer).returns(String) }")).to be(true)
    expect(excludes_nil?("sig { returns(::Integer) }")).to be(true)
    expect(excludes_nil?("sig(:final) { returns(String) }")).to be(true)
  end

  it "is true for T::Boolean and the generic collection types" do
    ["T::Boolean", "T::Array[Integer]", "T::Hash[String, Integer]", "T::Set[Symbol]"].each do |type|
      expect(excludes_nil?("sig { returns(#{type}) }")).to be(true), type
    end
  end

  it "is false whenever nil may be returned or the type is not certain" do
    ["T.nilable(String)", "T.untyped", "T.any(String, NilClass)", "T.anything", "NilClass", "Object",
     "SomeAlias", "T.noreturn"].each do |type|
      expect(excludes_nil?("sig { returns(#{type}) }")).to be(false), type
    end
  end

  it "is false for void and for a method without a sig" do
    expect(excludes_nil?("sig { void }")).to be(false)
    expect(described_class.new(subjects_in("class K\n  def m; end\nend\n").first).excludes_nil?).to be(false)
  end

  it "resolves a constant inside the method's own namespace first" do
    stub_const("DeclaredReturnProbe::Money", Class.new)
    expect(excludes_nil?("sig { returns(Money) }")).to be(true)
  end
end
