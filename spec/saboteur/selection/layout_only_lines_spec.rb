# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Selection::LayoutOnlyLines do
  def restricted(before, after, hunks, changed)
    described_class.new(hunks, base_source: before, current_source: after).restrict(Set.new(changed))
  end

  describe "a comment-only edit (#892)" do
    it "leaves a line out when only its trailing note was added" do
      expect(restricted("x = 1\ny = 2\n", "x = 1 # note\ny = 2\n", [[1, 1, 1, 1]], [1])).to be_empty
    end

    it "leaves a line out when only its trailing note was edited or removed" do
      before = "x = 1 # old\ny = 2 # keep\n"
      expect(restricted(before, "x = 1 # new\ny = 2 # keep\n", [[1, 1, 1, 1]], [1])).to be_empty
      expect(restricted(before, "x = 1\ny = 2 # keep\n", [[1, 1, 1, 1]], [1])).to be_empty
    end

    it "keeps a line whose code changed beside the note" do
      expect(restricted("x = 1\n", "x = 2 # note\n", [[1, 1, 1, 1]], [1])).to eq(Set[1])
    end

    it "keeps a line that was re-indented and also got a note" do
      expect(restricted("x = 1\n", "  x = 1 # note\n", [[1, 1, 1, 1]], [1])).to eq(Set[1])
    end

    it "keeps a line when a saboteur directive is added, edited or removed" do
      add = "x = 1 # saboteur:disable-line reason=\"known\"\n"
      expect(restricted("x = 1\n", add, [[1, 1, 1, 1]], [1])).to eq(Set[1])
      expect(restricted(add, "x = 1 # saboteur:disable-line reason=\"other\"\n", [[1, 1, 1, 1]], [1])).to eq(Set[1])
      expect(restricted(add, "x = 1 # note\n", [[1, 1, 1, 1]], [1])).to eq(Set[1])
      expect(restricted(add, "x = 1\n", [[1, 1, 1, 1]], [1])).to eq(Set[1])
    end

    it "pairs a line with its base line across an earlier hunk that added lines" do
      before = "a = 1\nb = 2\n"
      after = "a = 1\nnew = 0\nb = 2 # note\n"
      expect(restricted(before, after, [[1, 0, 2, 1], [2, 1, 3, 1]], [2, 3])).to eq(Set[2])
    end

    it "keeps a line whose __LINE__ moved, whatever the comment" do
      before = "n = __LINE__\n"
      after = "\nn = __LINE__ # note\n"
      expect(restricted(before, after, [[0, 0, 1, 1], [1, 1, 2, 1]], [1, 2])).to eq(Set[1, 2])
    end

    it "leaves a line out when a note replaces trailing spaces, or an unmoved __LINE__ got a note" do
      expect(restricted("x = 1  \n", "x = 1 # note\n", [[1, 1, 1, 1]], [1])).to be_empty
      expect(restricted("n = __LINE__\n", "n = __LINE__ # note\n", [[1, 1, 1, 1]], [1])).to be_empty
    end

    it "leaves a moved line out when it has no __LINE__, and only its note changed" do
      before = "def a\n  one\nend\n"
      after = "\ndef a\n  one # note\nend\n"
      expect(restricted(before, after, [[0, 0, 1, 1], [2, 1, 3, 1]], [1, 3])).to eq(Set[1])
    end

    it "keeps a line in a hunk that replaces a different number of lines" do
      expect(restricted("x = 1\n", "x = 1 # note\ny = 2\n", [[1, 1, 1, 2]], [1, 2])).to eq(Set[1, 2])
    end

    it "keeps a line where only the spacing around a token changed, with no note" do
      expect(restricted("x = a+b\n", "x = a + b\n", [[1, 1, 1, 1]], [1])).to eq(Set[1])
    end
  end
end
