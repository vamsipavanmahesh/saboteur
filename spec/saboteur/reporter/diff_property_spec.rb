# SPDX-License-Identifier: MIT
# frozen_string_literal: true

DiffHunk = Struct.new(:old_start, :old_count, :new_start, :new_count, :lines)

# Property checks on many random inputs: the diff, applied as a patch using
# only its own hunk headers, must rebuild the new text; it must be minimal
# (no more removed lines than needed); and its context must be exact.
RSpec.describe Saboteur::Reporter::Diff, "properties" do
  let(:first_line) { 7 }

  def random_lines(random, size)
    Array.new(size) { "line #{%w[a b c d].sample(random: random)}\n" }
  end

  def lcs_length(old_lines, new_lines)
    previous = Array.new(new_lines.size + 1, 0)
    old_lines.each do |old_line|
      current = [0]
      new_lines.each_with_index do |new_line, j|
        current << (old_line == new_line ? previous[j] + 1 : [previous[j + 1], current[j]].max)
      end
      previous = current
    end
    previous.last
  end

  def parse(diff)
    body = diff.lines.drop(2)
    hunks = []
    body.each do |line|
      if (header = line.match(/\A@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@\n\z/))
        hunks << DiffHunk.new(header[1].to_i, (header[2] || "1").to_i, header[3].to_i, (header[4] || "1").to_i, [])
      else
        hunks.last.lines << line
      end
    end
    hunks
  end

  # Applies the hunks to old_lines (numbered from first_line) and checks every
  # header against the lines the hunk really holds.
  def apply(old_lines, hunks)
    result = []
    cursor = 0
    hunks.each do |hunk|
      check_header(hunk)
      start = hunk.old_count.zero? ? hunk.old_start - first_line + 1 : hunk.old_start - first_line
      result.concat(old_lines[cursor...start])
      cursor = replay(hunk, old_lines, start, result)
    end
    result.concat(old_lines[cursor..])
  end

  def check_header(hunk)
    expect(hunk.lines.count { |l| !l.start_with?("+") }).to eq(hunk.old_count)
    expect(hunk.lines.count { |l| !l.start_with?("-") }).to eq(hunk.new_count)
  end

  # Replays one hunk onto result; returns the old-line cursor after it.
  def replay(hunk, old_lines, cursor, result)
    hunk.lines.each do |line|
      text = line[1..]
      expect(old_lines[cursor]).to eq(text) unless line.start_with?("+")
      result << text unless line.start_with?("-")
      cursor += 1 unless line.start_with?("+")
    end
    cursor
  end

  it "rebuilds the new text from the old one, minimally, for 300 random pairs" do
    random = Random.new(20_261_009)
    300.times do
      old_lines = random_lines(random, random.rand(0..12))
      new_lines = random_lines(random, random.rand(0..12))
      diff = described_class.unified(old_lines.join, new_lines.join, path: "f.rb", first_line: first_line)
      next expect(diff).to(eq("")) if old_lines == new_lines

      hunks = parse(diff)
      expect(apply(old_lines, hunks)).to eq(new_lines), diff
      removed = hunks.sum { |hunk| hunk.lines.count { |l| l.start_with?("-") } }
      expect(removed).to eq(old_lines.size - lcs_length(old_lines, new_lines)), diff
    end
  end

  it "keeps far-apart changes in separate hunks with at most three lines of context" do
    old_lines = (1..20).map { |n| "#{n}\n" }
    new_lines = old_lines.dup
    new_lines[1] = "two\n"
    new_lines[17] = "eighteen\n"
    hunks = parse(described_class.unified(old_lines.join, new_lines.join, path: "f.rb", first_line: 1))
    expect(hunks.map { |h| [h.old_start, h.old_count] }).to eq([[1, 5], [15, 6]])
  end

  it "numbers a pure insertion the way patch expects (line before, count 0)" do
    diff = described_class.unified("", "x\n", path: "f.rb", first_line: 10)
    expect(diff.lines[2]).to eq("@@ -9,0 +10 @@\n")
  end
end
