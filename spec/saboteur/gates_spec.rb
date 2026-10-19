# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Gates do
  def gates(settings = {})
    described_class.new({ "max_timeouts" => nil, "max_errors" => nil }.merge(settings))
  end

  def report(*statuses)
    report_of(*statuses.map { |status| result_for(status) })
  end

  describe ".limit" do
    it "reads a count, a percentage, or nothing" do
      expect(described_class.limit(nil, "max_errors")).to be_nil
      expect(described_class.limit("3", "max_errors")).to eq(3)
      expect(described_class.limit(0, "max_errors")).to eq(0)
      expect(described_class.limit(" 5% ", "max_errors")).to eq("5%")
      expect(described_class.limit("007", "max_errors")).to eq(7)
      expect(described_class.limit("05%", "max_errors")).to eq("5%")
      expect(described_class.limit("100%", "max_errors")).to eq("100%")
    end

    it "allows a count above 100, since only a percentage is capped" do
      expect(described_class.limit("250", "max_errors")).to eq(250)
    end

    it "refuses anything else and names the setting" do
      ["-1", "2.5", "abc", "", "101%", "%"].each do |value|
        expect { described_class.limit(value, "max_timeouts") }
          .to raise_error(Saboteur::ConfigError, /max_timeouts must be a count|max_timeouts percentage/), value
      end
    end
  end

  describe "per-path score gates (#473)" do
    around do |example|
      Dir.mktmpdir do |dir|
        @root = File.realpath(dir)
        example.run
      end
    end

    def subject_at(relative, index)
      path = File.join(@root, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "class Klass#{index}\n  def a; 1 > 0; end\nend\n")
      Saboteur::SubjectFinder.new.call(path).subjects.first
    end

    def result_on(subject, status)
      at = subject.file_source.index(">")
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1,
                                                replacement: ">=")
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison",
                                                        edits: [edit])
      Saboteur::MutantResult.new(subject:, mutation:, status:,
                                 mutated_source: subject.apply(mutation.edits))
    end

    def report_with(pairs, root: @root)
      results = pairs.map { |subject, status| result_on(subject, status) }
      Saboteur::Report.new(results:, subjects: results.map(&:subject), wall_time: 1.0, root:,
                           warnings: [], seed: 1,
                           operator_policy: Saboteur::Config.new({}).operator_policy)
    end

    def score_gates(pattern, min_score)
      described_class.new({ "max_timeouts" => nil, "max_errors" => nil,
                            "score_gates" => [{ "pattern" => pattern, "min_score" => min_score }] })
    end

    it "fails when a path gate's subset scores under its floor" do
      charge = subject_at("app/payments/charge.rb", 1)
      old = subject_at("app/legacy/old.rb", 2)
      report = report_with([[charge, :killed], [charge, :survived], [old, :killed], [old, :killed]])
      found = score_gates("app/payments/**/*", 90).violations(report)
      expect(found.map(&:cause)).to eq(["scoreGate"])
      expect(found.first.message).to include("app/payments/**/*", "score 50.0 below 90")
    end

    it "still matches gates when the project root is a symlink" do
      charge = subject_at("app/payments/charge.rb", 1)
      link = File.join(Dir.mktmpdir, "linked-root")
      File.symlink(@root, link)
      report = report_with([[charge, :killed], [charge, :survived]], root: link)
      expect(score_gates("app/payments/**/*", 90).violations(report).map(&:cause)).to eq(["scoreGate"])
    end

    it "passes when the subset meets its floor" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed], [charge, :survived]])
      expect(score_gates("app/payments/**/*", 50).violations(report)).to be_empty
    end

    it "passes when the subset scores strictly above its floor" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed], [charge, :killed], [charge, :survived]])
      expect(score_gates("app/payments/**/*", 50).violations(report)).to be_empty
    end

    it "passes vacuously when nothing executed under the gate, and says so" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed]])
      err = StringIO.new
      expect(score_gates("app/legacy/**/*", 95).failed?(report, err)).to be(false)
      expect(err.string).to include("app/legacy/**/*", "nothing executed")
    end

    it "prints the score-gate violation with its exact wording" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed], [charge, :survived]])
      err = StringIO.new
      expect(score_gates("app/payments/**/*", 90).failed?(report, err)).to be(true)
      expect(err.string).to eq("saboteur: score gate app/payments/**/*: score 50.0 below 90 " \
                               "(2 mutant(s) under it, 1 failing subject(s), " \
                               "1 matched file(s): app/payments/charge.rb)\n")
    end

    it "prints the vacuous note as one exact saboteur line, and never for an executed gate" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed]])
      g = described_class.new({ "max_timeouts" => nil, "max_errors" => nil,
                                "score_gates" => [{ "pattern" => "app/payments/**/*", "min_score" => 95 },
                                                  { "pattern" => "app/legacy/**/*", "min_score" => 95 }] })
      err = StringIO.new
      expect(g.failed?(report, err)).to be(false)
      expect(err.string).to eq("saboteur: score gate app/legacy/**/*: nothing executed under it, " \
                               "passing vacuously\n")
    end

    def two_gates(first, second)
      described_class.new({ "max_timeouts" => nil, "max_errors" => nil,
                            "score_gates" => [first, second] })
    end

    it "lists at most three matched files and counts the rest" do
      subjects = (1..5).map { |i| subject_at("app/payments/f#{i}.rb", i) }
      pairs = subjects.flat_map { |subject| [[subject, :killed], [subject, :survived]] }
      report = report_with(pairs)
      err = StringIO.new
      expect(score_gates("app/payments/**/*", 90).failed?(report, err)).to be(true)
      expect(err.string).to eq("saboteur: score gate app/payments/**/*: score 50.0 below 90 " \
                               "(10 mutant(s) under it, 5 failing subject(s), 5 matched file(s): " \
                               "app/payments/f1.rb, app/payments/f2.rb, app/payments/f3.rb, +2 more)\n")
    end

    it "scores a subject under the single most specific matching gate" do
      charge = subject_at("app/payments/charge.rb", 1)
      other = subject_at("app/other/thing.rb", 2)
      report = report_with([[charge, :killed], [charge, :survived], [other, :killed], [other, :killed]])
      g = two_gates({ "pattern" => "app/**/*", "min_score" => 90 },
                    { "pattern" => "app/payments/**/*", "min_score" => 95 })
      # app/**/* sees only app/other (score 100, holds); the payments gate
      # fails on charge alone. Independent scoring would fail app/**/* too.
      found = g.violations(report)
      expect(found.map(&:cause)).to eq(["scoreGate"])
      expect(found.first.message).to include("app/payments/**/*")
      expect(found.first.message).not_to include("score gate app/**/*:")
    end

    it "breaks a specificity tie by config order: the earlier gate wins" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed], [charge, :killed]])
      g = two_gates({ "pattern" => "app/payments/*", "min_score" => 90 },
                    { "pattern" => "app/payments/**", "min_score" => 90 })
      expect(g.violations(report)).to be_empty
      expect(g.score_gate_breakdowns(report).map { |b| b[:mutants] }).to eq([2, 0])
    end

    it "reports each gate that lost subjects to a more specific gate, even on a passing run" do
      charge = subject_at("app/payments/charge.rb", 1)
      other = subject_at("app/other/thing.rb", 2)
      report = report_with([[charge, :killed], [other, :killed]])
      g = two_gates({ "pattern" => "app/**/*", "min_score" => 50 },
                    { "pattern" => "app/payments/**/*", "min_score" => 50 })
      err = StringIO.new
      expect(g.failed?(report, err)).to be(false)
      expect(err.string).to eq("saboteur: score gate app/**/*: 1 subject(s) also match a more specific " \
                               "gate and score there\n")
    end

    it "reports a fully shadowed gate as overlapped, not vacuous" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed]])
      g = two_gates({ "pattern" => "app/**/*", "min_score" => 50 },
                    { "pattern" => "app/payments/**/*", "min_score" => 50 })
      err = StringIO.new
      expect(g.failed?(report, err)).to be(false)
      expect(err.string).to eq("saboteur: score gate app/**/*: 1 subject(s) also match a more specific gate " \
                               "and score there\n")
    end

    it "still reads a gate matching nothing at all as vacuous with gates overlapping elsewhere" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed]])
      g = two_gates({ "pattern" => "app/legacy/**/*", "min_score" => 95 },
                    { "pattern" => "app/payments/**/*", "min_score" => 50 })
      err = StringIO.new
      expect(g.failed?(report, err)).to be(false)
      expect(err.string).to eq("saboteur: score gate app/legacy/**/*: nothing executed under it, " \
                               "passing vacuously\n")
    end

    it "returns a machine-readable per-gate breakdown, nil without score gates" do
      charge = subject_at("app/payments/charge.rb", 1)
      other = subject_at("app/other/thing.rb", 2)
      report = report_with([[charge, :killed], [charge, :survived], [other, :killed]])
      g = two_gates({ "pattern" => "app/**/*", "min_score" => 50 },
                    { "pattern" => "app/payments/**/*", "min_score" => 95 })
      expect(g.score_gate_breakdowns(report)).to eq(
        [{ pattern: "app/**/*", minScore: 50, mutants: 1, tested: 1, score: 100.0, passed: true,
           failingSubjects: 0, files: ["app/other/thing.rb"] },
         { pattern: "app/payments/**/*", minScore: 95, mutants: 2, tested: 2, score: 50.0, passed: false,
           failingSubjects: 1, files: ["app/payments/charge.rb"] }]
      )
      expect(gates.score_gate_breakdowns(report)).to be_nil
    end

    it "reports a vacuous gate in the breakdown with a nil score" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed]])
      breakdown = score_gates("app/legacy/**/*", 95).score_gate_breakdowns(report).first
      expect(breakdown).to eq(pattern: "app/legacy/**/*", minScore: 95, mutants: 0, tested: 0,
                              score: nil, passed: true, failingSubjects: 0, files: [])
    end

    # 399 of 499 tested mutants killed is 79.96%: it displays as 80.0 but is
    # below an 80 floor. The violation and the JSON breakdown judge the
    # unrounded score through one shared verdict, so they cannot disagree.
    it "judges the unrounded score in both the violation and the breakdown" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with(([[charge, :killed]] * 399) + ([[charge, :survived]] * 100))
      g = score_gates("app/payments/**/*", 80)
      expect(g.violations(report).map(&:cause)).to eq(["scoreGate"])
      breakdown = g.score_gate_breakdowns(report).first
      expect(breakdown[:score]).to eq(80.0)
      expect(breakdown[:passed]).to be(false)
    end

    # A gate whose matched mutants all skipped, errored or timed out used to
    # pass silently; it passes vacuously and must say so, like the empty gate.
    it "warns when a gate matched mutants but tested none of them" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :skipped]])
      err = StringIO.new
      expect(score_gates("app/payments/**/*", 95).failed?(report, err)).to be(false)
      expect(err.string).to eq("saboteur: score gate app/payments/**/*: no mutant(s) tested under it, " \
                               "passing vacuously\n")
    end

    it "reports a shadowed gate as overlapped, not vacuous, even when nothing under it was tested" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :skipped]])
      g = two_gates({ "pattern" => "app/**/*", "min_score" => 50 },
                    { "pattern" => "app/payments/**/*", "min_score" => 50 })
      err = StringIO.new
      expect(g.failed?(report, err)).to be(false)
      # The shadowing gate won the mutant but tested none of it: overlap
      # note for the loser, vacuous note for the untested winner.
      expect(err.string).to eq("saboteur: score gate app/**/*: 1 subject(s) also match a more specific gate " \
                               "and score there\n" \
                               "saboteur: score gate app/payments/**/*: no mutant(s) tested under it, " \
                               "passing vacuously\n")
    end

    it "compares literal pattern text only: glob metacharacters add no specificity" do
      subject = subject_at("app/ab.rb", 1)
      report = report_with([[subject, :killed]])
      # Unstripped, both patterns are 7 characters; the literal runs are 5
      # and 6, so app/ab* wins only when metacharacters are stripped.
      g = two_gates({ "pattern" => "app/a?*", "min_score" => 50 },
                    { "pattern" => "app/ab*", "min_score" => 50 })
      expect(g.score_gate_breakdowns(report).map { |b| b[:mutants] }).to eq([0, 1])
    end

    # Direct pin on the counting rule: the replacement text and the * both
    # matter - an empty group still counts once ("x" -> "" and * -> + were
    # dogfood survivors on v5).
    it "counts each brace group as one literal, including an empty group" do
      g = score_gates("x", 1)
      expect(g.send(:specificity, "lib/{a,b}.rb")).to eq("lib/x.rb".length)
      expect(g.send(:specificity, "lib/{}.rb")).to eq("lib/x.rb".length)
    end

    it "counts one alternative per brace group, so an exact path outranks a brace expansion" do
      subject = subject_at("lib/saboteur/gates.rb", 1)
      report = report_with([[subject, :killed]])
      g = two_gates({ "pattern" => "lib/saboteur/{gates,config}.rb", "min_score" => 50 },
                    { "pattern" => "lib/saboteur/gates.rb", "min_score" => 50 })
      expect(g.score_gate_breakdowns(report).map { |b| [b[:pattern], b[:mutants]] })
        .to eq([["lib/saboteur/{gates,config}.rb", 0], ["lib/saboteur/gates.rb", 1]])
    end

    it "counts a failing subject once, however many of its mutants survived" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :survived], [charge, :survived]])
      err = StringIO.new
      expect(score_gates("app/payments/**/*", 90).failed?(report, err)).to be(true)
      expect(err.string).to include("2 mutant(s) under it, 1 failing subject(s)")
    end

    it "counts subjects lost to a more specific gate once per subject" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed], [charge, :killed]])
      g = two_gates({ "pattern" => "app/**/*", "min_score" => 50 },
                    { "pattern" => "app/payments/**/*", "min_score" => 50 })
      err = StringIO.new
      expect(g.failed?(report, err)).to be(false)
      expect(err.string).to include("app/**/*: 1 subject(s) also match a more specific gate")
    end

    it "lists every matched file when there are exactly three" do
      subjects = (1..3).map { |i| subject_at("app/payments/f#{i}.rb", i) }
      pairs = subjects.flat_map { |subject| [[subject, :killed], [subject, :survived]] }
      report = report_with(pairs)
      err = StringIO.new
      expect(score_gates("app/payments/**/*", 90).failed?(report, err)).to be(true)
      expect(err.string).to include("3 matched file(s): app/payments/f1.rb, app/payments/f2.rb, app/payments/f3.rb)")
      expect(err.string).not_to include("more")
    end

    it "lists three files and counts exactly one more at the boundary" do
      subjects = (1..4).map { |i| subject_at("app/payments/f#{i}.rb", i) }
      pairs = subjects.flat_map { |subject| [[subject, :killed], [subject, :survived]] }
      report = report_with(pairs)
      err = StringIO.new
      expect(score_gates("app/payments/**/*", 90).failed?(report, err)).to be(true)
      expect(err.string).to include("app/payments/f1.rb, app/payments/f2.rb, app/payments/f3.rb, +1 more)")
    end

    it "rounds the breakdown score to one decimal" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed], [charge, :killed], [charge, :survived]])
      breakdown = score_gates("app/payments/**/*", 50).score_gate_breakdowns(report).first
      expect(breakdown[:score]).to eq(66.7)
    end

    it "passes a gate whose score equals its floor" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with((1..9).map { [charge, :killed] } + [[charge, :survived]])
      breakdown = score_gates("app/payments/**/*", 90).score_gate_breakdowns(report).first
      expect(breakdown).to include(score: 90.0, passed: true)
    end

    it "counts toward any?, so --agent refuses the combination like --threshold" do
      expect(score_gates("app/**/*", 95).any?).to be(true)
    end
  end

  describe "#any? and #agent_option_name" do
    it "is true with --max-* limits alone and names them for the --agent rejection" do
      g = gates("max_timeouts" => 1)
      expect(g.any?).to be(true)
      expect(g.agent_option_name).to eq("--max-* gates")
    end

    it "is true with score gates alone and names them for the --agent rejection" do
      g = described_class.new({ "max_timeouts" => nil, "max_errors" => nil,
                                "score_gates" => [{ "pattern" => "app/**/*", "min_score" => 95 }] })
      expect(g.any?).to be(true)
      expect(g.agent_option_name).to eq("score gates")
    end

    it "is false with no gates at all" do
      expect(gates.any?).to be(false)
    end
  end

  describe "#violations" do
    it "passes when no gate is set, whatever the counts" do
      expect(gates.violations(report(:timeout, :error, :killed))).to be_empty
      expect(gates.any?).to be(false)
    end

    it "fails a count only when it is above the limit" do
      limit = gates("max_timeouts" => 1)
      expect(limit.violations(report(:timeout, :killed))).to be_empty
      found = limit.violations(report(:timeout, :timeout, :killed)).first
      expect(found.cause).to eq("maxTimeouts")
      expect(found.message).to eq("2 timeout mutants, above --max-timeouts 1")
    end

    it "treats a limit of 0 as no timeouts at all" do
      expect(gates("max_errors" => 0).violations(report(:killed, :killed))).to be_empty
      expect(gates("max_errors" => 0).violations(report(:killed, :killed, :killed, :error)).map(&:cause))
        .to eq(["maxErrors"])
    end

    it "compares a percentage with the executed mutants and ignores skipped ones" do
      limit = gates("max_errors" => "25%")
      expect(limit.violations(report(:error, :killed, :killed, :killed))).to be_empty
      expect(limit.violations(report(:error, :error, :killed, :killed, :killed, :skipped)).map(&:cause))
        .to eq(["maxErrors"])
    end

    it "is over a percentage only by the exact ratio" do
      limit = gates("max_errors" => "10%")
      expect(limit.violations(report(*[:error] * 100, *[:killed] * 900))).to be_empty
      expect(limit.violations(report(*[:error] * 100, *[:killed] * 899)).map(&:cause)).to eq(["maxErrors"])
      expect(limit.violations(report(*[:error] * 100, *[:killed] * 901))).to be_empty
    end

    it "reports each failed gate" do
      both = gates("max_timeouts" => 0, "max_errors" => 0)
      expect(both.violations(report(:timeout, :error, :killed, :killed, :killed)).map(&:cause))
        .to eq(%w[maxTimeouts maxErrors])
    end
  end

  describe "#failed?" do
    it "names the first failed gate as the cause when several fail" do
      both = gates("max_timeouts" => 0, "max_errors" => 0)
      expect(both.failed?(report(:timeout, :error, :killed), StringIO.new)).to be(true)
      expect(both.cause).to eq("maxTimeouts")
    end

    it "prints each failed gate and remembers the first cause" do
      err = StringIO.new
      limit = gates("max_timeouts" => 0)
      expect(limit.failed?(report(:timeout, :killed), err)).to be(true)
      expect(err.string).to eq("saboteur: 1 timeout mutants, above --max-timeouts 0\n")
      expect(limit.cause).to eq("maxTimeouts")
    end

    it "stays quiet and has no cause when every gate holds" do
      err = StringIO.new
      limit = gates("max_timeouts" => 5)
      expect(limit.failed?(report(:timeout, :killed), err)).to be(false)
      expect([err.string, limit.cause, limit.judges_errors?]).to eq(["", nil, false])
      expect(gates("max_errors" => 1).judges_errors?).to be(true)
    end
  end

  it "defines one flag per gate and passes the config key and raw value on" do
    parser = OptionParser.new
    given = {}
    described_class.define_options(parser) { |key, value| given[key] = value }
    parser.parse!(%w[--max-timeouts 3 --max-errors 5%])
    expect(given).to eq(max_timeouts: "3", max_errors: "5%")
    expect(parser.to_s).to include("--max-timeouts N", "--max-errors N",
                                   "Exit 1 when more than N mutants end as timeout (N or N%)",
                                   "Exit 1 when more than N mutants end as error (N or N%)")
  end
end
