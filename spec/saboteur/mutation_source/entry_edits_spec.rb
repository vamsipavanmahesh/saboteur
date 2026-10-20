# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"

RSpec.describe Saboteur::MutationSource::EntryEdits do
  let(:helper) { Class.new { include Saboteur::MutationSource::EntryEdits }.new }

  def parse(source)
    [Prism.parse(source).value.statements.body.first, Prism.lex(source).value.map(&:first)]
  end

  def elements_of(source)
    node, tokens = parse(source)
    [node.elements, node.location.end_offset - 1, tokens]
  end

  def separator(source, index)
    elements, ending, tokens = elements_of(source)
    helper.entry_separator(elements, index, ending, tokens)&.slice
  end

  it "deletes exactly the entry's bytes" do
    node, = parse("[aa, bb]")
    subject = Struct.new(:file).new("f.rb")
    edit = helper.delete_entry(subject, node.elements.first.location)
    expect([edit.file, edit.start_byte, edit.end_byte, edit.replacement]).to eq(["f.rb", 1, 3, ""])
  end

  it "takes the comma after an entry, else the one before the last entry" do
    expect(separator("[a, b, c]", 0)).to eq(",")
    expect(separator("[a, b, c]", 1)).to eq(",")
    elements, ending, tokens = elements_of("[a, b]")
    comma = helper.entry_separator(elements, 1, ending, tokens)
    expect(comma.start_offset).to eq(2)
  end

  it "needs no separator for the only entry or a whitespace-separated list" do
    expect(separator("[a]", 0)).to be_nil
    expect(separator("%w[a b]", 1)).to be_nil
  end

  it "recognises a heredoc entry, also nested inside the entry" do
    node, = parse("[<<~A, 1]\n  text\nA\n")
    expect(helper.heredoc?(node.elements.first)).to be(true)
    expect(helper.heredoc?(node.elements.last)).to be(false)
    nested, = parse("[foo(<<~A), 1]\n  text\nA\n")
    expect(helper.heredoc?(nested.elements.first)).to be(true)
  end
end
