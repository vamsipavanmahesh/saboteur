# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/regex_replacement"

RSpec.describe Saboteur::MutationSource::RegexReplacement do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body)
    subjects_in("class RegexExample\n  def check(input)\n    #{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits) }
  end

  it "drops each anchor and swaps each quantifier in scan order" do
    expect(replacements('input =~ /\A\d+\z/'))
      .to eq(["def check(input)\n    input =~ /\\d+\\z/\n  end",
              "def check(input)\n    input =~ /\\A\\d*\\z/\n  end",
              "def check(input)\n    input =~ /\\A\\d+/\n  end"])
  end

  it "swaps the + and * quantifiers" do
    expect(replacements("input =~ /a+b*/"))
      .to eq(["def check(input)\n    input =~ /a*b*/\n  end",
              "def check(input)\n    input =~ /a+b+/\n  end"])
  end

  it "drops line anchors too" do
    expect(replacements("input =~ /^abc$/"))
      .to eq(["def check(input)\n    input =~ /abc$/\n  end",
              "def check(input)\n    input =~ /^abc/\n  end"])
  end

  it "leaves escaped characters, character classes and lazy or possessive quantifiers alone" do
    expect(replacements("input =~ /a\\+b\\*c/")).to eq([])
    expect(replacements("input =~ /[^$a]/")).to eq([])
    expect(replacements("input =~ /a+?b*+c/")).to eq([])
  end

  it "keeps the mutation metadata" do
    subject = subject_for('input =~ /\A\d+\z/')
    mutation = source.mutations_for(subject).fetch(0)
    expect(mutation.operator).to eq("regex_replacement")
    expect(mutation.coarse).to be(false)
    expect(mutation.source).to eq("regex_replacement")
  end

  it "leaves interpolated regexes and non-regex literals alone" do
    expect(replacements("input =~ /\\A\#{prefix}\\d+\\z/")).to eq([])
    expect(replacements('input == "\\A\\d+\\z"')).to eq([])
  end

  it "tracks character classes so a quantifier after the class still mutates" do
    expect(replacements("input =~ /[a]+/")).to eq(["def check(input)\n    input =~ /[a]*/\n  end"])
    expect(replacements("input =~ /[\\A]/")).to eq([])
    expect(replacements("input =~ /[+]/")).to eq([])
  end

  it "leaves nested-repeat quantifiers alone even though Ruby merely warns (#135)" do
    expect(replacements("input =~ /a+*/")).to eq([])
  end

  it "keeps an unescaped closing bracket literal from swallowing a later quantifier" do
    expect(replacements("input =~ /a]+/")).to eq(["def check(input)
    input =~ /a]*/
  end"])
  end

  it "suppresses quantifiers inside POSIX classes and literal-[ classes (#135)" do
    expect(replacements("input =~ /[[:digit:]+]/")).to eq([])
    expect(replacements("input =~ /[[:digit:]*]/")).to eq([])
    expect(replacements("input =~ /[[+]*]/")).to eq(["def check(input)
    input =~ /[[+]+]/
  end"])
  end

  it "treats a quantifier after a literal space as a quantifier" do
    expect(replacements("input =~ /x +/")).to eq(["def check(input)\n    input =~ /x */\n  end"])
  end

  it "leaves possessive optional and possessive plus alone" do
    expect(replacements("input =~ /a?+/")).to eq([])
    expect(replacements("input =~ /a++/")).to eq([])
  end

  it "keeps scanning after an early backslash token" do
    expect(replacements("input =~ /\\d+\\z/"))
      .to eq(["def check(input)\n    input =~ /\\d*\\z/\n  end",
              "def check(input)\n    input =~ /\\d+/\n  end"])
  end

  it "skips arid expressions and nested definitions per the documented skip contract" do
    expect(replacements("def inner; /\\A\\d+\\z/; end")).to be_empty
    expect(described_class.new(arid: ["input"]).mutations_for(subject_for('input =~ /\A\d+\z/'))).to be_empty
  end
end
