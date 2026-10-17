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

  it "accepts edits that span the whole method exactly, and rejects a byte outside either end" do
    s = subject_under_test
    expect(s.apply([edit(s.start_byte, s.end_byte, "def m = 2\n  end")])).to eq("def m = 2\n  end")
    expect { s.apply([edit(s.start_byte - 1, s.start_byte + 1, "x")]) }.to raise_error(ArgumentError, /outside/)
    expect { s.apply([edit(s.end_byte - 1, s.end_byte + 1, "x")]) }.to raise_error(ArgumentError, /outside/)
  end

  it "names the edit range, the subject, and the subject span when an edit falls outside" do
    s = subject_under_test
    expect { s.apply([edit(0, 5, "x")]) }
      .to raise_error(ArgumentError, "edit 0...5 is outside A#m (#{s.start_byte}...#{s.end_byte})")
  end

  it "names the subject when edits overlap, and allows edits that only touch" do
    s = subject_under_test
    left = edit(s.start_byte, s.start_byte + 3, "x")
    touching = edit(s.start_byte + 3, s.start_byte + 6, "y")
    expect { s.apply([left, touching]) }.not_to raise_error
    expect { s.apply([left, edit(s.start_byte + 2, s.start_byte + 6, "y")]) }
      .to raise_error(ArgumentError, "overlapping edits in mutation of A#m")
  end

  it "applies edits given out of byte order" do
    s = subject_under_test
    first = edit(s.start_byte, s.start_byte + 3, "x")
    later = edit(s.start_byte + 3, s.start_byte + 6, "y")
    expect(s.apply([later, first])).to eq(s.apply([first, later]))
  end

  it "rejects edits for another file" do
    at = source.index(">=")
    expect { subject_under_test.apply([edit(at, at + 2, ">", file: "/elsewhere.rb")]) }
      .to raise_error(ArgumentError, "edit for /elsewhere.rb applied to subject in #{subject_under_test.file}")
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

    it "is true when any changed line lands inside, not only when all do" do
      expect(subject_under_test.overlaps_lines?(Set[3, 100])).to be(true)
      expect(subject_under_test.overlaps_lines?(Set[100, 200])).to be(false)
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
    it "maps an edit spanning two statements to the whole method" do
      two = subjects_in("class B\n  def m\n    a = 1\n    b = 2\n  end\nend\n").first
      source = two.file_source
      start = source.index("a = 1")
      edit = Saboteur::MutationSource::Edit.new(file: two.file, start_byte: start,
                                                end_byte: source.index("b = 2") + 5, replacement: "x")
      expect(two.coverage_lines_for(edit)).to eq(two.coverage_lines)
    end

    it "maps an edit in an empty method to the whole method" do
      empty = subjects_in("class A\n  def m\n  end\nend\n").first
      at = empty.file_source.index("def m") + 3
      edit = Saboteur::MutationSource::Edit.new(file: empty.file, start_byte: at, end_byte: at + 1,
                                                replacement: "x")
      expect(empty.coverage_lines_for(edit)).to eq(empty.coverage_lines)
    end

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

    it "uses the edit's last line, not its first, for a multi-line edit" do
      source = branchy.file_source
      start = source.index("x +")
      edit = Saboteur::MutationSource::Edit.new(file: branchy.file, start_byte: start,
                                                end_byte: source.index("2", start) + 1, replacement: "x")
      expect(branchy.coverage_lines_for(edit)).to eq([4, 5])
    end

    it "counts a trailing newline as the edit's last line" do
      source = branchy.file_source
      start = source.index("x +")
      edit = Saboteur::MutationSource::Edit.new(file: branchy.file, start_byte: start,
                                                end_byte: source.index("\n", start) + 1, replacement: "x")
      expect(branchy.coverage_lines_for(edit)).to eq([4])
    end

    it "crosses into the next line on the edit's final byte" do
      source = branchy.file_source
      start = source.index("x +")
      edit = Saboteur::MutationSource::Edit.new(file: branchy.file, start_byte: start,
                                                end_byte: source.index("\n", start) + 2, replacement: "x")
      expect(branchy.coverage_lines_for(edit)).to eq([4, 5])
    end

    it "maps an edit in a condition to the statement that holds it" do
      expect(branchy.coverage_lines_for(edit_at(">"))).to eq([3])
    end

    it "maps an edit outside every statement to the whole method" do
      expect(branchy.coverage_lines_for(edit_at("(x)"))).to eq(branchy.coverage_lines)
    end
  end

  describe "#coverage_lines_for with pattern matching" do
    let(:matchy) do
      subjects_in(<<~RUBY).first
        class A
          def m(x)
            case x
            in Integer then 1
            in String
              2
            end
          end
        end
      RUBY
    end

    def match_edit(text)
      at = matchy.file_source.index(text)
      Saboteur::MutationSource::Edit.new(file: matchy.file, start_byte: at, end_byte: at + text.bytesize,
                                         replacement: "x")
    end

    it "covers the case line and the in line for an edit exactly covering a pattern" do
      expect(matchy.coverage_lines_for(match_edit("Integer"))).to eq([3, 4])
    end

    it "covers the case line, the in line, and the body line for a multi-line clause" do
      expect(matchy.coverage_lines_for(match_edit("String"))).to eq([3, 5, 6])
    end

    it "falls back to the statement line for an edit inside a clause body" do
      expect(matchy.coverage_lines_for(match_edit("2"))).to eq([6])
    end

    it "covers a pattern from inside it, not only at its exact boundaries" do
      expect(matchy.coverage_lines_for(match_edit("Inte"))).to eq([3, 4])
    end

    it "maps an edit spanning two clauses" do
      source = matchy.file_source
      start = source.index("then")
      edit = Saboteur::MutationSource::Edit.new(file: matchy.file, start_byte: start,
                                                end_byte: source.index("String") + 3, replacement: "x")
      expect(matchy.coverage_lines_for(edit)).to eq([3, 4, 5])
    end

    it "handles an in clause with an empty body" do
      empty = subjects_in("class A\n  def m(x)\n    case x\n    in Integer\n    end\n  end\nend\n").first
      at = empty.file_source.index("Integer")
      edit = Saboteur::MutationSource::Edit.new(file: empty.file, start_byte: at, end_byte: at + 7,
                                                replacement: "x")
      expect(empty.coverage_lines_for(edit)).to eq([3, 4])
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

    it "is true when an explicit begin without rescue wraps a rescuing begin" do
      expect(recovers?("    begin\n      begin\n        work\n      rescue\n        1\n      end\n    end")).to be(true)
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

  it "keeps text before the def on its first line and after it on its last line" do
    inline = subjects_in("class A\n  x = 1; def m = 1; y = 2\nend\n").first
    expect(inline.surrounding_text).to eq(["  x = 1; ", "; y = 2"])
  end

  it "keeps the whole line when a one-line class leaves no newline around the def" do
    one_liner = subjects_in("class A; def x; 1; end; end").first
    expect(one_liner.surrounding_text).to eq(["class A; ", "; end"])
  end

  it "returns surrounding text in UTF-8" do
    expect(subject_under_test.surrounding_text.map(&:encoding)).to eq([Encoding::UTF_8, Encoding::UTF_8])
  end

  it "strings itself as its subject id" do
    expect(subject_under_test.to_s).to eq("A#m")
  end

  it "has no sig source without a sig, and the sig text with one" do
    expect(subject_under_test.sig_source).to be_nil
    sigged = subjects_in("class A\n  sig { params(x: Integer).returns(Integer) }\n  def m(x) = x\nend\n").first
    expect(sigged.sig_source).to eq("sig { params(x: Integer).returns(Integer) }")
  end
end
