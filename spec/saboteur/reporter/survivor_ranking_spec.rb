# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "timeout"

RSpec.describe Saboteur::Reporter::SurvivorRanking do
  def ranked_result(subject, first:, last: first, coarse: false, tests: [], replacement: "nil")
    lines = subject.file_source.lines
    start = lines.first(first - 1).join.bytesize
    finish = lines.first(last).join.bytesize - 1
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: start,
                                              end_byte: finish, replacement: replacement)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "ranking_probe",
                                                      edits: [edit], coarse: coarse)
    Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :survived,
                               mutated_source: subject.apply([edit]), covered_by: tests)
  end

  let(:subject) { subjects_in("class Ranked\n  def m\n    one\n    two\n    three\n    four\n  end\nend\n").first }

  def report_for(results, review: false, scope: nil)
    Saboteur::Report.new(results: results, subjects: [subject], wall_time: 0,
                         root: File.dirname(subject.file), review: review, diff_scope: scope)
  end

  it "prioritizes coarse, then coverage, then edited-line impact, then proximity" do
    coarse = ranked_result(subject, first: 3, coarse: true)
    covered = ranked_result(subject, first: 3, tests: %w[a b])
    broad = ranked_result(subject, first: 3, last: 4, tests: ["a"])
    near = ranked_result(subject, first: 6, tests: ["a"])
    far = ranked_result(subject, first: 3, tests: ["a"])
    scope = Saboteur::Engine::DiffScope.new(subject.file => Set[6])
    results = [far, near, broad, covered, coarse]
    report = report_for(results, scope: scope)
    expected = [coarse, covered, broad, near, far]
    expect(described_class.ordered(report, results)).to eq(expected)
    expect(described_class.ordered(report, results.reverse)).to eq(expected)
    expect(report.results).to eq(results)
  end

  it "counts distinct tests and edited lines once, with stable digest ties" do
    one = ranked_result(subject, first: 3, tests: %w[a a], replacement: "one_new")
    two = ranked_result(subject, first: 3, tests: ["a"], replacement: "two_new")
    report = report_for([two, one])
    expect(described_class.key(report, one)[0..2]).to eq([1, -1, -1])
    coarse = ranked_result(subject, first: 3, coarse: true)
    expect(described_class.key(report, coarse)[0]).to eq(0)
    expect(described_class.key(report, one)[3]).to eq(Float::INFINITY)
    expect(described_class.ordered(report, [two, one]).map(&:digest)).to eq([one.digest, two.digest].sort)
    duplicate = one.mutation.edits.first
    multi = one.mutation.with(edits: [duplicate, duplicate])
    allow(one).to receive(:mutation).and_return(multi)
    expect(described_class.edited_lines(one)).to eq([3])
  end

  it "ranks terminal display and JSON findings consistently, including review mode" do
    low = ranked_result(subject, first: 3)
    high = ranked_result(subject, first: 3, tests: %w[a b], replacement: "high")
    accepted = ranked_result(subject, first: 4, coarse: true)
    accepted.ignored = "reviewed"
    report = report_for([low, accepted, high])
    out = StringIO.new
    Saboteur::Reporter::Terminal.new(out, all_mutants: true).call(report)
    expect(out.string.index(high.digest)).to be < out.string.index(low.digest)
    expect(out.string).to include("Accepted (1, not scored)")
    expect(out.string.index("Accepted (")).to be > out.string.index(low.digest)
    findings = Saboteur::Reporter::Stryker.build(report).dig(:saboteur, :findings)
    expect(findings[:survivors].map { |item| item[:digest] }).to eq([high.digest, low.digest])
    expect(findings[:accepted].first[:digest]).to eq(accepted.digest)
    review = StringIO.new
    Saboteur::Reporter::Terminal.new(review, all_mutants: true).call(report_for([low, high], review: true))
    expect(review.string.index(high.digest)).to be < review.string.index(low.digest)
  end

  it "collapses same-statement mutants into one ranked block while JSON keeps the full ranked list" do
    first = ranked_result(subject, first: 3, coarse: true, tests: ["./spec/a_spec.rb[1:1]"],
                                   replacement: "first")
    middle = ranked_result(subject, first: 3, tests: %w[./spec/b_spec.rb[1:1] ./spec/b_spec.rb[1:2]],
                                    replacement: "middle")
    last = ranked_result(subject, first: 3, tests: ["./spec/a_spec.rb[1:1]"], replacement: "last")
    report = report_for([last, middle, first])
    out = StringIO.new
    Saboteur::Reporter::Terminal.new(out).call(report)
    ordered = described_class.ordered(report, [first, middle, last])
    listed = out.string.split("Next steps:").first
    expect(listed.scan(/^\d+\. \S+:\d+ \S+#/).size).to eq(1)
    expect(listed).to include(ordered.first.digest)
    sibling = listed.lines.find { |line| line.include?("more mutants here") }
    expect(sibling).to include(ordered[1].digest, ordered[2].digest)
    expect(sibling.index(ordered[1].digest)).to be < sibling.index(ordered[2].digest)
    expect(listed.scan("./spec/a_spec.rb[1:1]").size).to eq(1)
    findings = Saboteur::Reporter::Stryker.build(report).dig(:saboteur, :findings, :survivors)
    expect(findings.map { |finding| finding[:digest] }).to eq(ordered.map(&:digest))
  end

  it "measures distance to a whole edit span, and treats missing file changes as unknown" do
    scope = Saboteur::Engine::DiffScope.new(subject.file => Set[4])
    report = report_for([], scope: scope)
    expect(report.changed_line_distance(ranked_result(subject, first: 3, last: 5))).to eq(0)
    expect(report.changed_line_distance(ranked_result(subject, first: 6))).to eq(2)
    expect(report.changed_line_distance(ranked_result(subject, first: 3))).to eq(1)
    empty = report_for([], scope: Saboteur::Engine::DiffScope.new({}))
    expect(empty.changed_line_distance(ranked_result(subject, first: 3))).to be_nil
  end

  it "answers distance over a whole-file range without enumerating it" do
    huge = Class.new(Range) do
      def each(*) = raise("enumerated a huge range")

      def map(*) = raise("enumerated a huge range")

      def any?(*) = raise("enumerated a huge range")
    end.new(1, 10**15)
    scope = Saboteur::Engine::DiffScope.new(subject.file => huge)
    report = report_for([], scope: scope)
    Timeout.timeout(5) do
      expect(report.changed_line_distance(ranked_result(subject, first: 3, last: 5))).to eq(0)
    end
  end
  it "does not count the next line at an exclusive edit boundary" do
    result = ranked_result(subject, first: 3)
    edit = result.mutation.edits.first.with(end_byte: subject.file_source.lines.first(3).join.bytesize)
    allow(result).to receive(:mutation).and_return(result.mutation.with(edits: [edit]))
    expect(described_class.edited_lines(result)).to eq([3])
    scope = Saboteur::Engine::DiffScope.new(subject.file => Set[4])
    expect(report_for([], scope: scope).changed_line_distance(result)).to eq(1)
  end

  it "ranks unknown proximity after known proximity without changing coarse or coverage priorities" do
    near = ranked_result(subject, first: 3)
    unknown = ranked_result(subject, first: 4, replacement: "unknown")
    report = report_for([unknown, near])
    allow(report).to receive(:changed_line_distance).with(near).and_return(2)
    allow(report).to receive(:changed_line_distance).with(unknown).and_return(nil)
    expect(described_class.ordered(report, [unknown, near])).to eq([near, unknown])
    scope = Saboteur::Engine::DiffScope.new(subject.file => Set[])
    expect(report_for([], scope: scope).changed_line_distance(near)).to be_nil
  end
  it "counts a one-byte edit on the next line and a zero-width edit on its starting line" do
    result = ranked_result(subject, first: 3)
    boundary = subject.file_source.lines.first(3).join.bytesize
    edit = result.mutation.edits.first.with(end_byte: boundary + 1)
    allow(result).to receive(:mutation).and_return(result.mutation.with(edits: [edit]))
    expect(described_class.edited_lines(result)).to eq([3, 4])
    edit = edit.with(start_byte: boundary, end_byte: boundary)
    allow(result).to receive(:mutation).and_return(result.mutation.with(edits: [edit]))
    expect(described_class.edited_lines(result)).to eq([4])
  end
end
