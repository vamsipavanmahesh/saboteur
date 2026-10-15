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

    context "when the budget is the decider" do
      let(:config) { {} }

      it "records budgetExhausted even though survivors ran (control: budget outranks the verdict)" do
        expect(harness.agent_cause(report_stopped("max_duration"), "survivors")).to eq("budgetExhausted")
      end
    end
  end
end
