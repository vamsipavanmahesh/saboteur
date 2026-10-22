# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Report do
  let(:report) do
    report_of(result_for(:killed, runtime: 0.2), result_for(:killed, replacement: "<=", runtime: 0.4),
              result_for(:survived, replacement: "==", runtime: 0.3),
              result_for(:timeout, replacement: "!=", runtime: 5.0),
              result_for(:error, replacement: "<", runtime: 0.1),
              result_for(:skipped, replacement: ">", reason: "no coverage"))
  end

  it "carries every field into the unverified copy (#296)" do
    result = result_for(:killed, runtime: 0.5, killed_by: ["t1"], covered_by: %w[t1 t2],
                                 kill_cause: "assertion", executed: true)
    unverified = result.as_unverified("the --max-duration budget is spent")
    expect([unverified.status, unverified.reason, unverified.runtime, unverified.killed_by,
            unverified.covered_by, unverified.kill_cause, unverified.executed])
      .to eq([:unverified, "the --max-duration budget is spent", 0.5, ["t1"], %w[t1 t2], "assertion", true])
  end

  it "tells a flaky-check disagreement from a budget-cut unverified result (#1167)" do
    flaky = result_for(:killed).as_unverified("#{Saboteur::MutantResult::FLAKY_PREFIX}: first killed, then survived")
    expect(flaky.flaky?).to be(true)
    expect(result_for(:killed).as_unverified("the --max-duration budget is spent").flaky?).to be(false)
    expect(result_for(:killed).as_unverified(nil).flaky?).to be(false)
    expect(result_for(:survived, reason: "#{Saboteur::MutantResult::FLAKY_PREFIX}: x").flaky?).to be(false)
  end

  it "carries shard metadata when the run selected one shard" do
    shard = Saboteur::Engine::Shard.parse("1/2")
    report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1,
                                  root: File.dirname(person_subject.file), shard: shard)
    expect(report.shard).to be(shard)
    expect(report_of(result_for(:killed)).shard).to be_nil
  end

  it "freezes its own copy of the discovery failures (#589)" do
    failures = [{ file: "a.rb", message: "boom" }]
    report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), discovery_failures: failures)
    failures << { file: "b.rb", message: "later" }
    expect(report.discovery_failures).to eq([{ file: "a.rb", message: "boom" }])
    expect(report.discovery_failures).to be_frozen
  end

  it "keeps and freezes its own copy of the omissions, suppressions and memory" do
    omissions = [+"a"]
    suppressions = [+"b"]
    memory = { workers: [] }
    report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), omissions:,
                                  inline_suppressions: suppressions, memory:)
    expect([omissions, suppressions, memory].map(&:frozen?)).to eq([false, false, false])
    expect([report.omissions, report.inline_suppressions, report.memory]).to all(be_frozen)
  end

  it "counts every status separately" do
    expect(report.counts).to eq(killed: 2, survived: 1, timeout: 1, resource_limit: 0, error: 1,
                                skipped: 1, ran_at_load: 0, unreachable: 0, unverified: 0)
  end

  it "scores (killed + timeout) / (killed + survived + timeout), leaving errors and skips out" do
    expect(report.score).to eq(3.0 / 4)
  end

  it "has no score when nothing was tested" do
    expect(report_of(result_for(:error)).score).to be_nil
  end

  it "averages runtime over executed mutants only" do
    expect(report.mean_runtime).to be_within(1e-9).of((0.2 + 0.4 + 0.3 + 5.0 + 0.1) / 5)
  end

  it "leaves reused verdicts out of the mean runtime: they did not run" do
    report = report_of(result_for(:killed, runtime: 0.2), result_for(:killed, runtime: 9.0, reused: true))
    expect(report.mean_runtime).to eq(0.2)
  end

  it "keeps resource-limit stops out of the score, like errors" do
    report = report_of(result_for(:killed), result_for(:resource_limit, replacement: "<"))
    expect([report.counts[:resource_limit], report.score]).to eq([1, 1.0])
  end

  it "groups skip reasons" do
    expect(report.skip_reasons).to eq("no coverage" => 1)
  end

  it "separates ignored survivors" do
    survivor = report.survivors.first
    survivor.ignored = "equivalent"
    expect(report.unignored_survivors).to be_empty
  end
end

RSpec.describe Saboteur::MutantResult do
  it "rejects unknown statuses" do
    expect { result_for(:passed) }.to raise_error(ArgumentError, /unknown status/)
  end

  it "has a stable digest for the ignore list" do
    expect(result_for(:survived).digest).to eq(result_for(:killed).digest)
    expect(result_for(:survived).digest).not_to eq(result_for(:survived, replacement: "<=").digest)
  end

  it "renders a whole-line diff relative to the root" do
    diff = result_for(:survived).diff(root: File.dirname(person_subject.file))
    expect(diff).to include("--- a/person.rb", "-  def adult?; @age >= 18; end", "+  def adult?; @age > 18; end")
  end
end

RSpec.describe Saboteur::MutantResult, "pinned details" do
  it "names the rejected status in the error message" do
    expect { result_for(:passed) }.to raise_error(ArgumentError, "unknown status :passed")
  end

  it "has no ignore reason until one is set" do
    expect(result_for(:survived).ignored).to be_nil
    expect(result_for(:survived)).to be_unignored_survivor
  end

  it "carries the killed_by and runtime of the result into its error copy" do
    result = result_for(:killed, runtime: 0.5, killed_by: ["t1"], covered_by: %w[t1 t2], executed: true)
    errored = result.as_error("boom")
    expect([errored.runtime, errored.killed_by, errored.covered_by, errored.executed, errored.reason])
      .to eq([0.5, ["t1"], %w[t1 t2], true, "boom"])
  end

  it "computes the digest once and returns the same string afterwards" do
    result = result_for(:survived)
    expect(result.digest).to be(result.digest)
  end

  it "calls only a killed mutant with a non-assertion cause a crash kill" do
    expect(result_for(:survived, kill_cause: "NoMethodError").crash_kill?).to be(false)
    expect(result_for(:timeout, kill_cause: "NoMethodError").crash_kill?).to be(false)
    expect(result_for(:killed, kill_cause: "NoMethodError").crash_kill?).to be(true)
    expect(result_for(:killed, kill_cause: "assertion").crash_kill?).to be(false)
    expect(result_for(:killed).crash_kill?).to be(false)
  end

  describe "#diff" do
    let(:subject_double) do
      instance_double(Saboteur::Subject, file: "/proj/lib/a.rb", start_line: 7, source: "def a; 1; end",
                                         surrounding_text: ["  ", " # tail"])
    end
    let(:result) do
      described_class.new(subject: subject_double, mutation: comparison_mutation, status: :survived,
                          mutated_source: "def a; 2; end")
    end

    it "keeps the text around the subject on both sides of the diff and starts at the subject line" do
      expect(result.diff(root: "/proj")).to eq(
        "--- a/lib/a.rb\n+++ b/lib/a.rb\n@@ -7 +7 @@\n-  def a; 1; end # tail\n+  def a; 2; end # tail\n"
      )
    end

    it "uses the file path as it is without a root" do
      expect(result.diff).to start_with("--- a//proj/lib/a.rb\n")
    end

    it "keeps the path when the file is not below the root, even when the root is a name prefix" do
      expect(result.diff(root: "/pro")).to start_with("--- a//proj/lib/a.rb\n+++ b//proj/lib/a.rb\n")
    end

    it "keeps the path when the root merely appears inside the file name" do
      expect(result.diff(root: "/proj/lib/a")).to start_with("--- a//proj/lib/a.rb\n")
    end
  end
end

RSpec.describe Saboteur::MutantResult, "#assertion_kill?" do
  it "is true only for a killed mutant whose cause is an assertion" do
    expect(result_for(:killed, kill_cause: "assertion").assertion_kill?).to be(true)
    expect(result_for(:killed, kill_cause: "NoMethodError").assertion_kill?).to be(false)
    expect(result_for(:killed).assertion_kill?).to be(false)
  end

  it "is false for every status other than killed, whatever the cause" do
    %i[survived timeout error skipped].each do |status|
      expect(result_for(status, kill_cause: "assertion").assertion_kill?).to be(false)
    end
  end
end

RSpec.describe Saboteur::Report, "score without whole-body mutants" do
  let(:report) do
    report_of(result_for(:killed, coarse: true, kill_cause: "NoMethodError"),
              result_for(:killed, replacement: "<", kill_cause: "assertion"),
              result_for(:survived, replacement: "=="))
  end

  it "scores the fine mutants apart from the whole-body ones" do
    expect([report.score, report.fine_score_breakdown.value, report.coarse_score_breakdown.value])
      .to eq([2.0 / 3, 0.5, 1.0])
  end

  it "computes each breakdown once and returns the same object afterwards" do
    expect(report.score_breakdown).to equal(report.score_breakdown)
    expect(report.fine_score_breakdown).to equal(report.fine_score_breakdown)
    expect(report.coarse_score_breakdown).to equal(report.coarse_score_breakdown)
  end
  describe "#majority_errored?" do
    it "is true when more than half of the executed mutants errored" do
      expect(report_of(result_for(:killed), result_for(:error), result_for(:error)).majority_errored?).to be(true)
    end

    it "is false at exactly half" do
      expect(report_of(result_for(:killed), result_for(:error)).majority_errored?).to be(false)
    end

    it "is false with nothing executed" do
      expect(report_of(result_for(:skipped, reason: "no coverage")).majority_errored?).to be(false)
    end

    it "does not count skipped mutants in either side of the fraction" do
      report = report_of(result_for(:killed), result_for(:error), result_for(:error),
                         result_for(:skipped, reason: "no coverage"), result_for(:skipped, reason: "no coverage"))
      expect(report.majority_errored?).to be(true)
    end

    it "does not count resource-limited mutants as errors" do
      report = report_of(result_for(:killed), result_for(:error), result_for(:resource_limit, reason: "memory cap"))
      expect(report.majority_errored?).to be(false)
    end
  end
end
