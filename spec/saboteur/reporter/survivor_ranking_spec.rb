# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
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

  it "prioritizes same-statement survivors, then thin coverage, coarse, span and proximity" do
    coarse = ranked_result(subject, first: 3, coarse: true)
    covered = ranked_result(subject, first: 3, tests: %w[a b])
    broad = ranked_result(subject, first: 3, last: 4, tests: ["a"])
    near = ranked_result(subject, first: 6, tests: ["a"])
    far = ranked_result(subject, first: 3, tests: ["a"])
    scope = Saboteur::Engine::DiffScope.new(subject.file => Set[6])
    results = [far, near, broad, covered, coarse]
    report = report_for(results, scope: scope)
    # line 3 holds 4 mutants, so all of them outrank the lone line-6 mutant; inside the
    # statement: coarse, then fewest covering tests, then larger span, then proximity.
    expected = [coarse, broad, far, covered, near]
    expect(described_class.ordered(report, results)).to eq(expected)
    expect(described_class.ordered(report, results.reverse)).to eq(expected)
    expect(report.results).to eq(results)
  end

  it "counts distinct tests and edited lines once, with stable digest ties" do
    one = ranked_result(subject, first: 3, tests: %w[a a], replacement: "one_new")
    two = ranked_result(subject, first: 3, tests: ["a"], replacement: "two_new")
    report = report_for([two, one])
    expect(described_class.key(report, one)[0..2]).to eq([0, 1, 1])
    coarse = ranked_result(subject, first: 3, coarse: true)
    expect(described_class.key(report, coarse)[0]).to eq(0)
    expect(described_class.key(report, coarse)[2]).to eq(0)
    expect(described_class.key(report, one)[2]).to eq(1)
    expect(described_class.key(report, one)[4]).to eq(Float::INFINITY)
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
    expect(out.string.index(low.digest)).to be < out.string.index(high.digest)
    expect(out.string).to include("Accepted (1, not scored)")
    expect(out.string.index("Accepted (")).to be > out.string.index(low.digest)
    findings = Saboteur::Reporter::Stryker.build(report).dig(:saboteur, :findings)
    expect(findings[:survivors].map { |item| item[:digest] }).to eq([low.digest, high.digest])
    expect(findings[:accepted].first[:digest]).to eq(accepted.digest)
    review = StringIO.new
    Saboteur::Reporter::Terminal.new(review, all_mutants: true).call(report_for([low, high], review: true))
    expect(review.string.index(low.digest)).to be < review.string.index(high.digest)
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
  it "ranks a 4-mutant statement ahead of single-mutant statements, and thin coverage ahead of thick" do
    cluster = Array.new(4) { |i| ranked_result(subject, first: 3, tests: %w[a b], replacement: "s#{i}") }
    thin = ranked_result(subject, first: 4, tests: %w[a b], replacement: "thin")
    thick = ranked_result(subject, first: 5, tests: (1..21).map(&:to_s), replacement: "thick")
    results = [thick, thin, *cluster]
    ordered = described_class.ordered(report_for(results), results)
    expect(ordered.first(4)).to match_array(cluster)
    expect(ordered.index(thin)).to be < ordered.index(thick)
  end

  # P3 (#1160): the standing ranking regression fixture is the money gem
  # itself - lib/money/money/allocation.rb from RubyMoney/money v6.19.0 (MIT),
  # vendored byte-identical under spec/fixtures/projects/money_ranking (see
  # UPSTREAM.txt there) so the reviewer's line numbers stay real. The
  # reviewer run (external review #3, C2) saw 12 survivors: 4 mutants on the
  # remainder statement (allocation.rb:46, thin coverage) sat at #10 of 12
  # while allocation.rb:36 with 21 covering tests ranked #1. The remainder
  # statement must now rank in the top 2.
  it "ranks the money-gem remainder statement (allocation.rb:46) in the top 2 of 12 survivors" do
    fixture = File.expand_path("../../fixtures/projects/money_ranking/lib/money/money/allocation.rb", __dir__)
    source = File.read(fixture)
    expect(Digest::SHA256.hexdigest(source))
      .to eq("eba0d629515300e12216024ebb08dd119b37ca56eba8e6f9694b0d4d98b80a72")
    generate = subjects_in(source, name: "allocation.rb").find { |item| item.id == "Money::Allocation.generate" }
    expect(generate).not_to be_nil
    remainder = Array.new(4) { |i| ranked_result(generate, first: 46, tests: %w[a b], replacement: "rem#{i}") }
    allocation = ranked_result(generate, first: 36, tests: (1..21).map(&:to_s), replacement: "alloc")
    singles = [17, 25, 29, 32, 37, 41, 45].each_with_index.map do |line, i|
      ranked_result(generate, first: line, tests: (1..(3 + i)).map(&:to_s), replacement: "x#{i}")
    end
    all = [allocation, *singles, *remainder].shuffle(random: Random.new(7))
    expect(all.size).to eq(12)
    ordered = described_class.ordered(report_for(all), all)
    expect(ordered.first(4)).to match_array(remainder)
    expect(ordered.last).to eq(allocation)
  end

  it "pins the statement key shape: relative file, subject id, first mutated line" do
    result = ranked_result(subject, first: 3)
    report = report_for([result])
    expect(described_class.statement(report, result)).to eq([File.basename(subject.file), "Ranked#m", 3])
  end

  it "does not merge same-line mutants from different subjects into one statement" do
    one = ranked_result(subject, first: 3, replacement: "one_x")
    other = ranked_result(subject, first: 3, replacement: "other_x")
    twin = subject.dup
    allow(twin).to receive(:id).and_return("Ranked#other")
    allow(other).to receive(:subject).and_return(twin)
    report = report_for([one, other])
    expect(described_class.statement(report, one)).not_to eq(described_class.statement(report, other))
  end

  it "ranks coarse before non-coarse on otherwise identical survivors" do
    coarse = ranked_result(subject, first: 3, tests: ["a"], coarse: true, replacement: "coarse_x")
    plain = ranked_result(subject, first: 3, tests: ["a"], replacement: "plain_x")
    report = report_for([plain, coarse])
    expect(described_class.ordered(report, [plain, coarse]).first).to eq(coarse)
  end

  it "pins the documented ordering" do
    ordering = [
      "surviving mutants per statement descending, then fewer covering tests,",
      "coarse first, larger edited-line span, nearer changed lines,",
      "then file, line and digest"
    ].join(" ")
    expect(described_class::ORDERING).to eq(ordering)
  end
end
