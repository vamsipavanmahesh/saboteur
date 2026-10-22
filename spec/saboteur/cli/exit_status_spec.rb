# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::CLI::ExitStatus do
  let(:harness) do
    Class.new do
      include Saboteur::CLI::ExitStatus

      attr_reader :config, :err

      def initialize(config)
        @config = config
        @err = StringIO.new
        @out = StringIO.new
      end

      def agent_cause(report, verdict) = agent_exit_cause(report, { verdict: verdict })

      def code(report) = exit_code(report)

      attr_writer :format

      def cause(report, code) = exit_cause(report, code)

      def surv_cause(report) = survivors_cause(report)

      def quality_gate?(report) = failed_quality_gate?(report)
      def ignore_empty?(report) = empty_clean_diff?(report)
    end.new(config)
  end

  def report_stopped(reason, truncated: [])
    instance_double(
      Saboteur::Report,
      early_stop: Saboteur::EarlyStop.new(reason: reason, unreached: [], truncated: truncated, unverified: []),
      executed: [instance_double(Saboteur::MutantResult, status: :alive)],
      majority_errored?: false
    )
  end

  # The triage states reach the real exit gates through IgnoreList.load +
  # apply, not through a stubbed report (#304 QA).
  describe "ignore-list triage states through the real gates" do
    let(:config) { {} }

    def with_ignore_file(survivor, state)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "saboteur_ignore.rb")
        File.write(path, <<~RUBY)
          Saboteur.ignore do |i|
            i.mutation "#{survivor.digest}", subject: "Person#adult?", reason: "triaged", state: "#{state}"
          end
        RUBY
        yield Saboteur::IgnoreList.load(path)
      end
    end

    def triaged_report(state, survivor)
      with_ignore_file(survivor, state) { |list| list.apply([survivor]) }
      report_of(survivor, result_for(:killed))
    end

    {
      "accepted_equivalent" => false,
      "wont_fix" => false,
      "todo" => true
    }.each do |state, fails|
      it "#{state} #{fails ? 'fails' : 'passes'} the survivor gate and exit code" do
        survivor = result_for(:survived)
        with_ignore_file(survivor, state) do |list|
          # The fail-fast check and the survivor gate both read accepts?
          # before apply marks anything: only an accepting state shields.
          expect(list.accepts?(survivor)).to be(!fails)
          list.apply([survivor])
        end
        report = report_of(survivor, result_for(:killed))
        expect(harness.quality_gate?(report)).to be(fails)
        expect(harness.code(report)).to eq(fails ? Saboteur::CLI::EXIT_SURVIVORS : Saboteur::CLI::EXIT_OK)
      end
    end

    context "with --threshold the score decides, and the states do not change it" do
      let(:config) { { "threshold" => 50.0 } }

      it "passes all three states at the same score" do
        %w[accepted_equivalent wont_fix todo].each do |state|
          gate = harness.quality_gate?(triaged_report(state, result_for(:survived)))
          expect(gate).to be(false), "state #{state} changed the score"
        end
      end
    end
  end

  describe "agent_exit_cause" do
    context "when --max-duration-ok leaves the exit to the verdict and survivors ran" do
      let(:config) { { "max_duration_ok" => true } }

      it "records the survivor verdict, not failFast: the budget stop is not a fail-fast stop (#245)" do
        expect(harness.agent_cause(report_stopped("max_duration"), "survivors")).to eq("survivors")
      end

      it "still records failFast for a real --fail-fast stop (control)" do
        expect(harness.agent_cause(report_stopped("fail_fast"), "survivors")).to eq("failFast")
      end
    end

    context "when the budget stopped the sole subject mid-way" do
      let(:config) { {} }

      it "still exits 4 with an executed prefix and no unreached subject (#245)" do
        report = report_stopped("max_duration", truncated: [{ subject: "K#m", omitted: 2 }])
        expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_BUDGET)
        expect(harness.agent_cause(report, "clean")).to eq("budgetExhausted")
      end
    end

    context "with --max-duration-ok and nothing verified (#296)" do
      let(:config) { { "max_duration_ok" => true } }

      def unverified_stop(tested)
        instance_double(
          Saboteur::Report,
          early_stop: Saboteur::EarlyStop.new(reason: "max_duration", unreached: %w[K#m], truncated: [],
                                              unverified: []),
          score_breakdown: instance_double(Saboteur::Score, tested: tested),
          majority_errored?: false,
          review?: false,
          subjects: [],
          results: [],
          executed: [],
          unignored_survivors: [instance_double(Saboteur::MutantResult)]
        )
      end

      it "exits 3 when the budget stop left only unverified results: no verified verdict, no score" do
        report = unverified_stop(0)
        expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_TOOL)
        expect(harness.err.string).to include("no score to judge")
      end

      it "lets a run with verified verdicts through to the verdict (control)" do
        expect(harness.code(unverified_stop(3))).to eq(Saboteur::CLI::EXIT_SURVIVORS)
      end
    end

    context "when a --flaky-check rerun disagreed (#1167)" do
      let(:config) { {} }
      let(:flaky) do
        instance_double(Saboteur::MutantResult, flaky?: true, digest: "abc123")
      end

      def flaky_report(results)
        instance_double(Saboteur::Report, early_stop: nil, results: results, review?: false, executed: [],
                                          majority_errored?: false)
      end

      it "exits 3 with its own sentence, never the budget exit, and records incomplete" do
        report = flaky_report([flaky])
        expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_TOOL)
        expect(harness.err.string).to eq(
          "saboteur: 1 mutant changed verdict on the --flaky-check reordered rerun (abc123), so they are " \
          "unverified: your tests depend on run order; fix that and run again\n"
        )
        expect(harness.cause(report, Saboteur::CLI::EXIT_TOOL)).to eq("incomplete")
      end

      it "pluralises and names at most three digests" do
        many = Array.new(4) { |i| instance_double(Saboteur::MutantResult, flaky?: true, digest: "d#{i}") }
        harness.code(flaky_report(many))
        expect(harness.err.string).to include("4 mutants changed verdict", "(d0, d1, d2)")
        expect(harness.err.string).not_to include("d3")
      end
    end

    context "when the budget is the decider" do
      let(:config) { {} }

      it "records budgetExhausted even though survivors ran (control: budget outranks the verdict)" do
        expect(harness.agent_cause(report_stopped("max_duration"), "survivors")).to eq("budgetExhausted")
      end
    end
  end

  describe "exit_cause for an incomplete run" do
    let(:config) { {} }

    def partial_report(early_stop:, tested:, majority_errored: false)
      instance_double(
        Saboteur::Report,
        early_stop: early_stop,
        score_breakdown: instance_double(Saboteur::Score, tested: tested),
        majority_errored?: majority_errored,
        review?: false,
        subjects: [],
        results: [],
        executed: []
      )
    end

    let(:stop) { Saboteur::EarlyStop.new(reason: "max_duration", unreached: [], truncated: [], unverified: []) }

    it "is incomplete when an early stop left nothing tested (#296)" do
      expect(harness.cause(partial_report(early_stop: stop, tested: 0), Saboteur::CLI::EXIT_TOOL)).to eq("incomplete")
    end

    it "is incompleteUnderThreshold when the stop left some results tested (#296)" do
      expect(harness.cause(partial_report(early_stop: stop, tested: 3), Saboteur::CLI::EXIT_TOOL))
        .to eq("incompleteUnderThreshold")
    end

    it "is incompleteUnderThreshold without an early stop, even with nothing tested (#296)" do
      expect(harness.cause(partial_report(early_stop: nil, tested: 0), Saboteur::CLI::EXIT_TOOL))
        .to eq("incompleteUnderThreshold")
    end

    it "is errorMajority when errors dominate (control)" do
      expect(harness.cause(partial_report(early_stop: nil, tested: 0, majority_errored: true),
                           Saboteur::CLI::EXIT_TOOL)).to eq("errorMajority")
    end
  end

  describe "fail-fast vs other early-stop reasons (#296)" do
    let(:config) { {} }

    def gate_report(reason)
      instance_double(
        Saboteur::Report,
        early_stop: Saboteur::EarlyStop.new(reason: reason, unreached: [], truncated: [], unverified: []),
        unignored_survivors: []
      )
    end

    it "names failFast in survivors_cause only for a fail_fast stop" do
      expect(harness.surv_cause(gate_report("fail_fast"))).to eq("failFast")
      expect(harness.surv_cause(gate_report("max_duration"))).to eq("survivors")
    end

    it "fails the quality gate automatically only for a fail_fast stop" do
      expect(harness.quality_gate?(gate_report("fail_fast"))).to be(true)
      expect(harness.quality_gate?(gate_report("max_duration"))).to be(false)
    end
  end
  describe "a scoped run whose subjects were all skipped (#574)" do
    let(:config) { {} }

    def review_report(skipped:, results: [], review: true, subjects: nil)
      subjects ||= skipped.keys
      Saboteur::Report.new(results:, subjects:, wall_time: 1.0, root: File.dirname(subjects.first.file),
                           review:, seed: 1, skipped_subjects: skipped,
                           operator_policy: Saboteur::Config.new({}).operator_policy)
    end

    it "exits 3 and names each skipped subject with its reason" do
      report = review_report(skipped: { person_subject => "refinements" })
      expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_TOOL)
      expect(harness.err.string).to include("Person#adult?").and include("refinements").and include("not verified")
    end

    it "records incomplete as the exit cause, not incompleteUnderThreshold" do
      report = review_report(skipped: { person_subject => "refinements" })
      expect(harness.cause(report, Saboteur::CLI::EXIT_TOOL)).to eq("incomplete")
    end

    it "leaves a full run with skipped subjects green" do
      report = review_report(skipped: { person_subject => "refinements" }, review: false)
      expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_OK)
      expect(harness.err.string).to be_empty
    end

    context "when the unverifiable scope is also an empty --since diff" do
      let(:config) { { "since" => "main" } }

      it "still exits 3 instead of passing as an empty clean diff" do
        report = review_report(skipped: { person_subject => "refinements" })
        expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_TOOL)
        expect(harness.ignore_empty?(report)).to be(false)
        expect(harness.err.string).to include("was skipped (refinements)")
        expect(harness.err.string).not_to include("no mutants in the diff")
      end
    end

    # A review of zero subjects verified nothing only when subjects exist
    # and were all skipped; an empty subject list is just a green run
    # (#587 dogfood).
    it "does not call a review with no subjects unverifiable" do
      report = Saboteur::Report.new(results: [], subjects: [], wall_time: 1.0,
                                    root: File.dirname(person_subject.file),
                                    review: true, seed: 1, skipped_subjects: {},
                                    operator_policy: Saboteur::Config.new({}).operator_policy)
      expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_OK)
      expect(harness.err.string).to be_empty
    end

    it "prints the full skipped-subject sentence" do
      report = review_report(skipped: { person_subject => "refinements" })
      harness.code(report)
      expect(harness.err.string).to include("saboteur: Person#adult? (person.rb:2) was skipped (refinements), " \
                                            "so the change under test was not verified")
    end

    describe "when the run already announced the skip (#1227)" do
      let(:announced) { "Person#adult? (person.rb:2): skipped (refinements); its change is not verified by this run" }

      def announced_report(lines)
        Saboteur::Report.new(results: [], subjects: [person_subject], wall_time: 1.0,
                             root: File.dirname(person_subject.file), review: true, seed: 1,
                             skipped_subjects: { person_subject => "refinements" }, live_announced: lines,
                             operator_policy: Saboteur::Config.new({}).operator_policy)
      end

      it "still exits 3 but does not repeat the subject in the gate sentence" do
        expect(harness.code(announced_report([announced]))).to eq(Saboteur::CLI::EXIT_TOOL)
        expect(harness.err.string).to eq("")
      end

      %w[json agent].each do |format|
        it "keeps the gate sentence for --format #{format}" do
          harness.format = format
          expect(harness.code(announced_report([announced]))).to eq(Saboteur::CLI::EXIT_TOOL)
          expect(harness.err.string).to include("Person#adult? (person.rb:2) was skipped (refinements)")
        end
      end

      it "keeps the sentence when the announcement named another reason or another subject" do
        other = announced.sub("(refinements)", "(no coverage)")
        harness.code(announced_report([other, "Other#x (person.rb:2): skipped (refinements); not verified"]))
        expect(harness.err.string).to include("was skipped (refinements)")
      end

      it "does not take a longer reason that starts the same way for the announced one" do
        longer = announced.sub("(refinements)", "(refinements and more)")
        harness.code(announced_report([longer]))
        expect(harness.err.string).to include("was skipped (refinements)")
      end

      it "repeats only the subjects the announcement did not name" do
        refined = subjects_in("class Refined\n  def x\n    1\n  end\nend\n", name: "refined.rb").first
        report = Saboteur::Report.new(results: [], subjects: [person_subject, refined], wall_time: 1.0,
                                      root: File.dirname(person_subject.file), review: true, seed: 1,
                                      skipped_subjects: { person_subject => "refinements",
                                                          refined => "refinements" },
                                      live_announced: [announced],
                                      operator_policy: Saboteur::Config.new({}).operator_policy)
        harness.code(report)
        expect(harness.err.string).to include("Refined#x")
        expect(harness.err.string).not_to include("Person#adult?")
      end
    end

    it "judges the run by its results when other subjects ran" do
      refined = subjects_in("class Refined\n  def x\n    1\n  end\nend\n", name: "refined.rb").first
      report = review_report(skipped: { refined => "refinements" },
                             subjects: [person_subject, refined],
                             results: [result_for(:killed)])
      expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_OK)
    end
  end

  describe "a review run whose mutants all ran unreachable (#597)" do
    let(:config) { {} }

    def unreachable_report(results:, review: true)
      Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1.0,
                           root: File.dirname(person_subject.file), review:, seed: 1,
                           skipped_subjects: {}, operator_policy: Saboteur::Config.new({}).operator_policy)
    end

    it "exits 3 instead of going silently green" do
      report = unreachable_report(results: [result_for(:unreachable), result_for(:unreachable)])
      expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_TOOL)
      expect(harness.err.string).to include("unreachable").and include("not verified")
    end

    it "records incomplete as the exit cause, not incompleteUnderThreshold" do
      report = unreachable_report(results: [result_for(:unreachable)])
      expect(harness.cause(report, Saboteur::CLI::EXIT_TOOL)).to eq("incomplete")
    end

    it "keeps a normal verdict when any mutant was judged" do
      report = unreachable_report(results: [result_for(:unreachable), result_for(:killed)])
      expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_OK)
    end

    it "fails a full run the same way: unreachable mutants verified nothing" do
      report = unreachable_report(results: [result_for(:unreachable)], review: false)
      expect(harness.code(report)).to eq(Saboteur::CLI::EXIT_TOOL)
    end
  end

  describe "--ignore-empty" do
    let(:config) { {} }

    # The empty_report double carries no skipped-subject state; the real
    # predicate is pinned through code in the all-skipped block (#574).
    let(:harness) do
      Class.new do
        include Saboteur::CLI::ExitStatus

        attr_reader :config, :err

        def initialize(config)
          @config = config
          @err = StringIO.new
          @out = StringIO.new
        end

        def unverifiable_scope?(_report) = false

        def ignore_empty?(report) = empty_clean_diff?(report)
      end.new(config)
    end

    def empty_report(results, omissions: [], inline_suppressions: [], discovery_failures: [], invalid_mutations: 0)
      instance_double(Saboteur::Report, results:, omissions:, inline_suppressions:, discovery_failures:,
                                        invalid_mutations:)
    end

    context "with the flag and --since set" do
      let(:config) { { "ignore_empty" => true, "since" => "main" } }

      it "is true and notes when the run selected no mutants" do
        expect(harness.ignore_empty?(empty_report([]))).to be(true)
        expect(harness.err.string).to include("no mutants in the diff")
      end

      it "is false when the run selected mutants" do
        expect(harness.ignore_empty?(empty_report([:result]))).to be(false)
      end

      it "is false when the empty diff still carries omissions" do
        expect(harness.ignore_empty?(empty_report([], omissions: ["1 mutant omitted"]))).to be(false)
      end

      it "is false when the empty diff's mutants were all inline-suppressed" do
        expect(harness.ignore_empty?(empty_report([], inline_suppressions: ["Person#adult?"]))).to be(false)
      end

      it "is false when the diff's mutants were dropped because they did not parse (#1265)" do
        expect(harness.ignore_empty?(empty_report([], invalid_mutations: 2))).to be(false)
        expect(harness.err.string).to be_empty
      end

      it "is false when mutant discovery failed in the diff" do
        expect(harness.ignore_empty?(empty_report([], discovery_failures: ["lib/a.rb: parse error"]))).to be(false)
      end
    end

    it "is false without --since, flag or not" do
      expect(harness.ignore_empty?(empty_report([]))).to be(false)
    end

    context "with the flag but no --since (a no-op, #1266)" do
      let(:config) { { "ignore_empty" => true } }

      it "is false and silent" do
        expect(harness.ignore_empty?(empty_report([]))).to be(false)
        expect(harness.err.string).to be_empty
      end
    end

    context "with --since but no flag" do
      let(:config) { { "since" => "main" } }

      it "is true and notes: the zero-mutant pass is the default (#1142)" do
        expect(harness.ignore_empty?(empty_report([]))).to be(true)
        expect(harness.err.string).to include("no mutants in the diff")
      end
    end
  end
end
