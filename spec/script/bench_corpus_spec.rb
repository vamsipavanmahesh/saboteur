# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../../script/bench_corpus"

RSpec.describe BenchCorpus do
  def mutant(status, from, to = from)
    { "status" => status, "location" => { "start" => { "line" => from }, "end" => { "line" => to } } }
  end

  describe ".hunks" do
    let(:diff) do
      <<~DIFF
        diff --git a/lib/a.rb b/lib/a.rb
        --- a/lib/a.rb
        +++ b/lib/a.rb
        @@ -10 +10,2 @@ def x
        @@ -20,3 +21 @@
        @@ -40,0 +41,2 @@
        --- a/spec/a_spec.rb
        +++ b/spec/a_spec.rb
        @@ -5,2 +5,2 @@
        --- /dev/null
        +++ b/spec/new_spec.rb
        @@ -0,0 +1,4 @@
      DIFF
    end

    it "gives the parent-side lines of each hunk per file" do
      expect(described_class.hunks(diff)).to eq("lib/a.rb" => [10..10, 20..22, 40..41], "spec/a_spec.rb" => [5..6])
    end
  end

  describe ".classify" do
    let(:ranges) { [10..12] }

    it "is exact when a mutant that was not detected overlaps the fixed lines" do
      expect(described_class.classify([mutant("Killed", 11), mutant("Survived", 12, 13)], ranges)).to eq(:catch_exact)
      expect(described_class.classify([mutant("NoCoverage", 9, 10)], ranges)).to eq(:catch_exact)
    end

    it "is near within NEAR lines of the hunk and a miss beyond it" do
      expect(described_class.classify([mutant("Survived", 17)], ranges)).to eq(:catch_near)
      expect(described_class.classify([mutant("Survived", 18)], ranges)).to eq(:miss)
      expect(described_class.classify([mutant("Survived", 5)], ranges)).to eq(:catch_near)
      expect(described_class.classify([mutant("Survived", 4)], ranges)).to eq(:miss)
    end

    it "ignores killed mutants on the fixed lines and says so when there are none" do
      expect(described_class.classify([mutant("Killed", 11), mutant("Timeout", 10)], ranges)).to eq(:miss)
      expect(described_class.classify([], ranges)).to eq(:no_mutants)
    end
  end

  describe ".verdict" do
    it "takes the strongest result across files" do
      expect(described_class.verdict("a" => :miss, "b" => :catch_near)).to eq(:catch_near)
      expect(described_class.verdict("a" => :no_mutants, "b" => :miss)).to eq(:miss)
      expect(described_class.verdict({})).to eq(:no_mutants)
    end
  end

  describe ".table" do
    it "lists each fix and counts the catches" do
      rows = [{ name: "jwt", fix: "24ec3d8abc", verdict: "catch_exact", expected: "catch_exact", mutants: 9, open: 2 },
              { name: "grape", fix: "d978262abc", verdict: "miss", expected: "miss", mutants: 5, open: 1 }]

      text = described_class.table(rows)

      expect(text).to include("| jwt | 24ec3d8a | catch_exact | catch_exact | 9 | 2 |")
      expect(text).to end_with("Caught 1 of 2.")
    end
  end
end
