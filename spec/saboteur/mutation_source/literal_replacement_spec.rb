# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/literal_replacement"

RSpec.describe Saboteur::MutationSource::LiteralReplacement do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body, prefix: "")
    subjects_in("#{prefix}class LiteralExample\n  def apply(input)\n    #{body}\n  end\nend\n").first
  end

  def found_for(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| [mutation.operator, subject.apply(mutation.edits)] }
  end

  { "true" => "false", "false" => "true" }.each do |original, replacement|
    it "swaps #{original} for #{replacement} and a return assertion kills it" do
      subject = subject_for("input ? #{original} : nil")
      mutation = source.mutations_for(subject).fetch(0)
      expect(mutation.operator).to eq("literal_boolean")
      expect(mutation.source).to eq("literal_replacement")
      expect(mutation.coarse).to be(false)
      correct = Class.new { class_eval(subject.source) }.new
      changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
      expected = original == "true"
      expect(correct.apply(true)).to eq(expected)
      expect { expect(changed.apply(true)).to eq(expected) }
        .to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end

  it "empties a static string and an exact-value assertion kills it" do
    subject = subject_for('input + "token"')
    mutation = source.mutations_for(subject).fetch(0)
    expect(mutation.operator).to eq("literal_string")
    correct = Class.new { class_eval(subject.source) }.new
    changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
    expect(correct.apply("prefix:")).to eq("prefix:token")
    expect { expect(changed.apply("prefix:")).to eq("prefix:token") }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it "handles quoted and percent strings, escapes and multibyte bytes" do
    ['"héllo"', "'héllo'", "%q[héllo]", "%Q{héllo}", '"\\n"'].each do |literal|
      found = found_for("input + #{literal}")
      expect(found).to eq([["literal_string", "def apply(input)\n    input + \"\"\n  end"]]), literal
    end
  end

  it "does not invent a value for an already empty string" do
    ['""', "''", "%q[]"].each { |literal| expect(found_for(literal)).to be_empty }
  end

  it "does not replace interpolation fragments, word-list elements, symbols, regexes or commands" do
    ["\"hello \#{true}\"", "%w[hello world]", "%i[hello world]", ':"hello"', "/hello/", "`hello`"].each do |body|
      expect(found_for(body)).to be_empty, body
    end
  end

  it "does not change literal expressions inside other text nodes" do
    [':"hello #{true}"', '/hello#{true}/', '`hello#{true}`'].each do |body| # rubocop:disable Lint/InterpolationCheck
      expect(found_for(body)).to be_empty, body
    end
  end

  it "leaves heredoc declarations and bodies untouched" do
    expect(found_for("<<~TEXT\n      hello\n    TEXT")).to be_empty
  end

  it "does not enter arid statements, including nested literals" do
    expect(found_for('logger.info("token", true)')).to be_empty
    custom = described_class.new(arid: [/\Atrack\b/])
    expect(custom.mutations_for(subject_for('track("token", false)'))).to be_empty
  end

  it "accepts arid pattern strings and regexes alike" do
    subject = subject_for('track("token", true)')
    ["\\Atrack\\b", /\Atrack\b/].each do |pattern|
      expect(described_class.new(arid: [pattern]).mutations_for(subject)).to be_empty
    end
  end

  it "does not change default parameter values" do
    subject = subjects_in('class LiteralExample; def apply(input = "token"); input; end; end').first
    expect(source.mutations_for(subject)).to be_empty
  end

  it "leaves block and lambda parameter defaults untouched while visiting their bodies" do
    ["input.map { |value = true| [value, false] }",
     '->(value = "token") { [value, false] }',
     'lambda { |value: "token"| [value, false] }',
     '->(value: "token") { [value, false] }'].each do |body|
      mutations = found_for(body)
      expect(mutations.size).to eq(1), body
      expect(mutations.first.first).to eq("literal_boolean")
      expect(mutations.first.last).to include(body.sub("false]", "true]"))
    end
  end

  it "stops at nested definitions and singleton classes" do
    ["def inner; true; end", 'class << input; def inner; "token"; end; end'].each do |body|
      expect(found_for(body)).to be_empty, body
    end
  end

  it "stops at class and module nodes" do
    ["class Nested; def inner; true; end; end", 'module Nested; def inner; "token"; end; end'].each do |body|
      subject = double("subject", node: double("definition", body: Prism.parse(body).value.statements))
      expect(source.mutations_for(subject)).to be_empty
    end
  end

  it "orders nested literals by source and creates distinct parseable mutations" do
    subject = subject_for('[true, false, "token", ""]')
    found = source.mutations_for(subject)
    expect(found.map(&:operator)).to eq(%w[literal_boolean literal_boolean literal_string])
    texts = found.map { |mutation| subject.apply(mutation.edits) }
    expect(texts.uniq.size).to eq(3)
    expect(texts).to all(satisfy { |text| Prism.parse(text).success? })
    offsets = found.map { |mutation| mutation.edits.first.start_byte }
    expect(offsets).to eq(offsets.sort)
  end

  ["true", "false", '"token"'].each do |literal|
    it "keeps the #{literal} digest stable when a multibyte comment shifts the method" do
      digests = ["", "# héllo\n"].map do |prefix|
        subject = subject_for("[input, #{literal}]", prefix: prefix)
        source.mutations_for(subject).fetch(0).digest(subject_start: subject.start_byte,
                                                      original_source: subject.file_source)
      end
      expect(digests.uniq.size).to eq(1)
    end
  end

  it "appends literal mutations after existing builtin proposals" do
    subject = subject_for('[input + 1, true, "token"]')
    found = Saboteur::MutationSource::Builtin.new.mutations_for(subject)
    expect(found.first(2).map(&:operator)).to eq(%w[body_nil body_raise])
    # Newer sources append after the literal operators; assert their
    # relative order, not the absolute tail.
    operators = found.map(&:operator)
    expect(operators.index("literal_string")).to be > operators.index("literal_boolean")
  end
end
