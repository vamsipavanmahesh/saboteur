# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "timeout"

RSpec.describe Saboteur::Subject do
  let(:source) { "class A\n  def m(x)\n    x >= 1\n  end\nend\n" }
  let(:subject_under_test) { subjects_in(source).first }

  def edit(start_byte, end_byte, replacement, file: subject_under_test.file)
    Saboteur::MutationSource::Edit.new(file:, start_byte:, end_byte:, replacement:)
  end

  it "takes the body from the block for a define_method subject, from the def otherwise (#194)" do
    dm = subjects_in("class A\n  define_method(:m) { |x| x * 2 }\nend\n").first
    expect(dm.body_node).to be_a(Prism::StatementsNode)
    expect(dm.body_node.location.slice).to eq("x * 2")
    expect(subject_under_test.body_node).to be_a(Prism::StatementsNode)
    expect(subject_under_test.body_node.location.slice).to eq("x >= 1")
  end

  it "applies byte-range edits to the method text only" do
    at = source.index(">=")
    expect(subject_under_test.apply([edit(at, at + 2, ">")])).to eq("def m(x)\n    x > 1\n  end")
  end

  it "applies several non-overlapping edits regardless of order" do
    op = source.index(">=")
    one = source.index("1\n")
    text = subject_under_test.apply([edit(op, op + 2, "<"), edit(one, one + 1, "2")])
    expect(text).to eq("def m(x)\n    x < 2\n  end")
  end

  it "rejects edits outside the method" do
    expect { subject_under_test.apply([edit(0, 5, "module")]) }.to raise_error(ArgumentError, /outside/)
  end

  it "rejects overlapping edits" do
    at = source.index(">=")
    expect { subject_under_test.apply([edit(at, at + 2, ">"), edit(at + 1, at + 3, "x")]) }
      .to raise_error(ArgumentError, /overlapping/)
  end

  it "rejects edits for another file" do
    at = source.index(">=")
    expect { subject_under_test.apply([edit(at, at + 2, ">", file: "/elsewhere.rb")]) }
      .to raise_error(ArgumentError, /applied to subject/)
  end

  it "maps body lines (not the def line) for multi-line methods" do
    expect(subject_under_test.coverage_lines).to eq([3, 4])
  end

  it "maps the def line for one-line methods" do
    expect(subjects_in("class A\n  def m; 1; end\nend\n").first.coverage_lines).to eq([2])
  end

  describe "#overlaps_lines?" do
    it "answers a changed-lines set by scanning it" do
      expect(subject_under_test.overlaps_lines?(Set[3])).to be(true)
      expect(subject_under_test.overlaps_lines?(Set[1, 5])).to be(false)
    end

    it "answers a range by interval overlap, not by enumerating it" do
      expect(subject_under_test.overlaps_lines?(3..3)).to be(true)
      expect(subject_under_test.overlaps_lines?(2..5)).to be(true)
      expect(subject_under_test.overlaps_lines?(2..2)).to be(true)
      expect(subject_under_test.overlaps_lines?(4..4)).to be(true)
      expect(subject_under_test.overlaps_lines?(5..9)).to be(false)
      expect(subject_under_test.overlaps_lines?(1..1)).to be(false)
      huge = Class.new(Range) do
        def each(*) = raise("enumerated a huge range")

        def map(*) = raise("enumerated a huge range")

        def any?(*) = raise("enumerated a huge range")
      end.new(5, 10**15)
      Timeout.timeout(5) do
        expect(subject_under_test.overlaps_lines?(huge)).to be(false)
      end
    end
  end

  describe "#coverage_lines_for" do
    let(:branchy) do
      subjects_in(<<~RUBY).first
        class A
          def m(x)
            if x > 1
              total = x +
                      2
            else
              x - 1
            end
          end
        end
      RUBY
    end

    def edit_at(text, occurrence = 0)
      source = branchy.file_source
      at = -1
      (occurrence + 1).times { at = source.index(text, at + 1) }
      Saboteur::MutationSource::Edit.new(file: branchy.file, start_byte: at, end_byte: at + text.bytesize,
                                         replacement: "x")
    end

    it "maps an edit to its innermost statement's first line through the edit's last line" do
      expect(branchy.coverage_lines_for(edit_at("2"))).to eq([4, 5])
      expect(branchy.coverage_lines_for(edit_at("x - 1"))).to eq([7])
    end

    it "maps an edit in a condition to the statement that holds it" do
      expect(branchy.coverage_lines_for(edit_at(">"))).to eq([3])
    end

    it "maps an edit outside every statement to the whole method" do
      expect(branchy.coverage_lines_for(edit_at("(x)"))).to eq(branchy.coverage_lines)
    end
  end

  describe "#recovers?" do
    def recovers?(body)
      subjects_in("class A\n  def m\n#{body}\n  end\nend\n").first.recovers?
    end

    it "is true for a method-level rescue or else, a modifier rescue, or a nested begin/rescue" do
      expect(recovers?("    work\n  rescue\n    1")).to be(true)
      expect(recovers?("    work rescue 1")).to be(true)
      expect(recovers?("    x = begin\n      work\n    rescue\n      1\n    end\n    x")).to be(true)
    end

    it "is false for a method with no rescue anywhere" do
      expect(recovers?("    work\n    1")).to be(false)
    end

    it "is false for an ensure-only body and for a rescue inside a nested def" do
      expect(recovers?("    work\n  ensure\n    done")).to be(false)
      expect(recovers?("    def inner\n      x\n    rescue\n      1\n    end\n    work")).to be(false)
    end
  end

  describe "#line_of" do
    it "gives the 1-based file line of a byte offset" do
      source = subject_under_test.file_source
      expect(subject_under_test.line_of(0)).to eq(1)
      expect(subject_under_test.line_of(source.index("def"))).to eq(2)
      expect(subject_under_test.line_of(source.index(">="))).to eq(3)
      expect(subject_under_test.line_of(source.index("\n"))).to eq(1)
    end
  end

  it "returns the text around the def on its first and last lines" do
    expect(subject_under_test.surrounding_text).to eq(["  ", ""])
  end
end
