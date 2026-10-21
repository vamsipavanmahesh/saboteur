# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "reporter pins" do
  let(:source) { "class Sample\n  def run\n    first = 1\n    second = 2\n  end\nend\n" }
  let(:target) { subjects_in(source).first }

  def edit(text, replacement)
    at = target.file_source.index(text)
    Saboteur::MutationSource::Edit.new(file: target.file, start_byte: at, end_byte: at + text.size, replacement:)
  end

  def result_with(*edits)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: target.id, operator: "x", edits: edits,
                                                      coarse: false)
    Saboteur::MutantResult.new(subject: target, mutation:, status: :survived, mutated_source: target.apply(edits))
  end

  describe Saboteur::Reporter::SurvivorRanking do
    let(:report) do
      Saboteur::Report.new(results: [], subjects: [target], wall_time: 0, root: File.dirname(target.file))
    end

    it "ranks by the path relative to the root and by the line of the earliest edit" do
      result = result_with(edit("second = 2", "a"), edit("first = 1", "b"))
      key = described_class.key(report, result)
      expect(key[5]).to eq(File.basename(target.file))
      expect(key[6]).to eq(3)
    end
  end

  describe Saboteur::Reporter::MutationText do
    it "turns invalid bytes into replacement characters without touching a frozen replacement" do
      frozen = "ok\xFF".dup.force_encoding(Encoding::BINARY).freeze
      expect(described_class.replacement(result_with(edit("first = 1", frozen)))).to eq("ok\uFFFD")
    end

    it "folds a bare line break and one with space on only one side" do
      ["a\nb", "a \nb", "a\n b"].each do |text|
        expect(described_class.replacement(result_with(edit("first = 1", text)))).to eq("a b"), text.inspect
      end
    end

    it "folds a line break and the space around it into one space and trims the ends" do
      expect(described_class.replacement(result_with(edit("first = 1", "  a  \n\n   b  ")))).to eq("a b")
    end
  end

  describe Saboteur::Reporter::NextSteps do
    it "indents the ignore entry under its heading" do
      survivor = result_for(:survived)
      out = StringIO.new
      described_class.new(out, Saboteur::Reporter::Palette.for(out, mode: :never)).call(report_of(survivor))
      expect(out.string.lines).to include(
        %(      i.mutation "#{survivor.digest}", subject: "#{survivor.subject.id}", reason: "why it is equivalent"\n)
      )
    end
  end

  describe Saboteur::Reporter::ReviewComments do
    def finding(**changes)
      { "digest" => "aabbccdd11223344", "path" => "lib/x.rb", "operator" => "comparison", "original" => "a",
        "replacement" => "b", "classification" => "missing_test",
        "changedLines" => [12] }.merge(changes.transform_keys(&:to_s))
    end

    it "posts a finding only when every one of its conditions holds" do
      expect(described_class.plan({ "survivors" => [finding] }).post.size).to eq(1)
      bad = [finding(digest: "xyz"), finding(path: nil), finding(changedLines: "12"), finding(changedLines: []),
             finding(changedLines: [0]), finding(classification: "likely_equivalent"),
             finding(classification: "arid")]
      bad.each do |one|
        expect(described_class.plan({ "survivors" => [one] }).post).to eq([]), one.inspect
      end
    end

    it "does not count a finding it can never place among the ones it could not post" do
      unplaced = described_class.plan({ "survivors" => [finding(changedLines: [0])] })
      expect(unplaced.summary).to eq(described_class.plan({ "survivors" => [] }).summary)
      placeable = described_class.plan({ "survivors" => [finding] }, locate: ->(_) {})
      expect(placeable.summary).not_to eq(unplaced.summary)
    end
  end
end
