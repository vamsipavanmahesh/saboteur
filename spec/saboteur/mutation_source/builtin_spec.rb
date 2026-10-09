# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::Builtin do
  def mutations(body, params: "(a, b)")
    subject = subjects_in("class K\n  def m#{params}\n#{body}\n  end\nend\n").first
    mutated_texts(subject).map { |operator, text| [operator, text.lines[1..-2].join.strip] }
  end

  def texts(body, operator, **)
    mutations(body, **).select { |op, _| op == operator }.map(&:last)
  end

  describe "coarse" do
    it "replaces the body with nil and with raise, before anything else" do
      found = mutations("    a >= b")
      expect(found.first(2)).to eq([%w[body_nil nil], %w[body_raise raise]])
    end

    it "marks only body replacements as coarse" do
      subject = subjects_in("class K\n  def m(a)\n    a + 1\n  end\nend\n").first
      coarse = described_class.new.mutations_for(subject).select(&:coarse).map(&:operator)
      expect(coarse).to eq(%w[body_nil body_raise])
    end

    it "does not replace a body that is already nil, or that is only arid statements" do
      expect(texts("    nil", "body_nil")).to be_empty
      expect(texts("    puts a\n    logger.info(b)", "body_nil")).to be_empty
    end

    it "replaces a body that does real work before an arid last line" do
      expect(texts("    a = b + 1\n    puts a", "body_nil")).to eq(["nil"])
    end

    it "does not raise inside a body whose rescue catches it (the stop would hide every fine mutant)" do
      ["rescue", "rescue => e", "rescue StandardError", "rescue Exception => e"].each do |clause|
        clause = clause.tr("\\", "")
        subject = subjects_in("class K\n  def m\n    work\n  #{clause}\n    1\n  end\nend\n").first
        expect(mutated_texts(subject).map(&:first)).not_to include("body_raise"), clause
      end
    end

    it "still raises inside a body whose rescue catches only specific errors" do
      subject = subjects_in("class K\n  def m\n    work\n  rescue ArgumentError\n    1\n  end\nend\n").first
      expect(mutated_texts(subject).map(&:first)).to include("body_raise")
    end

    it "keeps rescue clauses when replacing the body" do
      subject = subjects_in("class K\n  def m\n    work\n  rescue StandardError\n    1\n  end\nend\n").first
      text = mutated_texts(subject).to_h.fetch("body_nil")
      expect(text).to eq("def m\n    nil\n  rescue StandardError\n    1\n  end")
    end

    it "handles endless defs" do
      subject = subjects_in("class K\n  def m = 1 + 2\nend\n").first
      expect(mutated_texts(subject).first).to eq(["body_nil", "def m = nil"])
    end

    it "generates nothing for an empty method" do
      expect(mutations("", params: "")).to be_empty
    end
  end

  describe "comparison" do
    it "swaps each comparison operator" do
      expect(texts("    a >= b", "comparison")).to eq(["a > b", "a <= b"])
      expect(texts("    a > b", "comparison")).to eq(["a >= b", "a < b"])
      expect(texts("    a <= b", "comparison")).to eq(["a < b", "a >= b"])
      expect(texts("    a < b", "comparison")).to eq(["a <= b", "a > b"])
      expect(texts("    a == b", "comparison")).to eq(["a != b"])
      expect(texts("    a != b", "comparison")).to eq(["a == b"])
    end
  end

  describe "boolean logic" do
    it "swaps && with || and and with or" do
      expect(texts("    a && b", "boolean_logic")).to eq(["a || b"])
      expect(texts("    a or b", "boolean_logic")).to eq(["a and b"])
    end

    it "removes negation" do
      expect(texts("    !a.empty?", "negation_removal")).to eq(["a.empty?"])
    end

    it "replaces if/unless/ternary conditions with true and false" do
      expect(texts("    return 1 if a > b", "condition_true")).to eq(["return 1 if true"])
      expect(texts("    a ? 1 : 2", "condition_false")).to eq(["false ? 1 : 2"])
      expect(texts("    unless a\n      1\n    end", "condition_true")).to eq(["unless true\n      1\n    end"])
    end

    it "skips the loop condition replacement that can never end the loop" do
      expect(texts("    while a\n      b\n    end", "condition_true")).to be_empty
      expect(texts("    while a\n      b\n    end", "condition_false")).to eq(["while false\n      b\n    end"])
      expect(texts("    until a\n      b\n    end", "condition_false")).to be_empty
    end
  end

  describe "arithmetic" do
    it "swaps + with - and * with /" do
      expect(texts("    a + b", "arithmetic")).to eq(["a - b"])
      expect(texts("    a * b", "arithmetic")).to eq(["a / b"])
    end

    it "leaves string concatenation alone" do
      expect(texts('    "x" + b', "arithmetic")).to be_empty
    end

    it "changes numeric literals to n+1, n-1 and 0" do
      expect(texts("    a + 5", "literal_number")).to eq(["a + 6", "a + 4", "a + 0"])
      expect(texts("    a + 1.5", "literal_number")).to eq(["a + 2.5", "a + 0.5", "a + 0.0"])
      expect(texts("    a + 0", "literal_number")).to eq(["a + 1", "a + (-1)"])
    end
  end

  describe "statements" do
    it "removes each statement of a multi-statement body" do
      expect(texts("    a = 1\n    b = 2\n    a + b", "statement_removal").size).to eq(3)
    end

    it "does not remove the only statement of the body (coarse covers it)" do
      expect(texts("    a + b", "statement_removal")).to be_empty
    end

    it "does not treat expression slots as statements" do
      expect(texts("    x = a ? b : 1\n    y = \"\#{a ? 1 : 2}\"\n    return 1 if a", "statement_removal"))
        .to eq(["nil\n    y = \"\#{a ? 1 : 2}\"\n    return 1 if a",
                "x = a ? b : 1\n    nil\n    return 1 if a"])
    end

    it "does not remove an if/unless without else (the condition mutants are the same change)" do
      body = "    return 1 if a\n    b unless a\n    if a\n      b\n    else\n      c\n    end\n    d"
      removed = texts(body, "statement_removal")
      expect(removed.size).to eq(2) # the if/else and `d`
      expect(removed).to all(include("return 1 if a", "b unless a"))
    end

    it "removes statements inside multi-statement nested bodies" do
      # b, c and d; the else-less if itself is covered by condition_false.
      expect(texts("    if a\n      b\n      c\n    end\n    d", "statement_removal").size).to eq(3)
    end

    it "never mutates arid statements" do
      found = mutations("    logger.info(a + 1)\n    a > b").reject { |op, _| op.start_with?("body_") }
      expect(found.map(&:last)).to all(include("logger.info(a + 1)"))
    end

    it "accepts custom arid patterns" do
      source = described_class.new(arid: ['\Atrack\b'])
      subject = subjects_in("class K\n  def m(a)\n    track(a + 1)\n    a\n  end\nend\n").first
      fine = mutated_texts(subject, source:).reject { |op, _| op.start_with?("body_") }
      expect(fine.map(&:last)).to all(include("track(a + 1)"))
    end
  end

  describe "nil handling" do
    it "turns &. into ." do
      expect(texts("    a&.b", "safe_navigation")).to eq(["a.b"])
    end

    it "turns ||= into =" do
      expect(texts("    @x ||= a", "or_assign")).to eq(["@x = a"])
      expect(texts("    h[a] ||= b", "or_assign")).to eq(["h[a] = b"])
    end
  end

  it "produces text that parses for every mutation of a varied method" do
    body = <<~RUBY.gsub(/^/, "    ")
      return nil unless a&.valid?
      total = 0
      a.items.each { |i| total += i.price * 2 if i.price >= 10 && !i.free? }
      @cache ||= {}
      total > 100 ? total - 5 : total
    RUBY
    expect(mutations(body).map(&:last)).to all(satisfy { |text| Prism.parse("def m\n#{text}\nend").success? })
  end

  it "does not mutate inside nested scopes" do
    expect(mutations("    class << a\n      def x = 1 + 1\n    end\n    a").map(&:first)).not_to include("arithmetic")
  end
end
