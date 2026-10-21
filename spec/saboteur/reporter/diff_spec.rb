# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Reporter::Diff do
  it "renders a one-line change with real file line numbers" do
    diff = described_class.unified("  def a? = x >= 1\n", "  def a? = x > 1\n", path: "lib/a.rb", first_line: 14)
    expect(diff).to eq(<<~DIFF)
      --- a/lib/a.rb
      +++ b/lib/a.rb
      @@ -14 +14 @@
      -  def a? = x >= 1
      +  def a? = x > 1
    DIFF
  end

  it "shows up to three lines of context and merges nearby changes" do
    original = (1..10).map { |n| "line #{n}\n" }.join
    mutated = original.sub("line 5", "LINE 5").sub("line 7", "LINE 7")
    diff = described_class.unified(original, mutated, path: "f.rb", first_line: 1)
    expect(diff.lines.grep(/^@@/)).to eq(["@@ -2,9 +2,9 @@\n"])
    expect(diff).to include("-line 5\n+LINE 5\n", " line 6\n", "-line 7\n+LINE 7\n")
  end

  it "renders a removed line" do
    diff = described_class.unified("a\nb\nc\n", "a\nc\n", path: "f.rb", first_line: 10)
    expect(diff).to include("@@ -10,3 +10,2 @@", "-b\n")
  end

  it "returns an empty string when nothing changed" do
    expect(described_class.unified("a\n", "a\n", path: "f.rb")).to eq("")
  end

  it "terminates a last line that has no newline" do
    expect(described_class.unified("a", "b", path: "f.rb")).to end_with("-a\n+b\n")
  end

  describe ".edit_span" do
    def edit(at, length, replacement)
      Saboteur::MutationSource::Edit.new(file: "f.rb", start_byte: at, end_byte: at + length,
                                         replacement: replacement)
    end

    it "spans the replacement text exactly, relative to the line start" do
      expect(described_class.edit_span(100, [edit(111, 3, "years")])).to eq([11, 5])
    end

    it "starts at the earliest edit and sums single-line replacement lengths" do
      expect(described_class.edit_span(0, [edit(10, 2, "aa"), edit(4, 1, "bbb")])).to eq([4, 5])
    end

    it "still marks one column for a pure removal" do
      expect(described_class.edit_span(7, [edit(9, 5, "")])).to eq([2, 1])
    end

    it "counts only the first line of a multi-line replacement" do
      expect(described_class.edit_span(0, [edit(2, 1, "aaaa\nbb")])).to eq([2, 4])
    end
  end
end
