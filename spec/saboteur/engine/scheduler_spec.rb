# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Scheduler do
  describe ".prioritize" do
    it "puts tests that killed earlier mutants first and keeps the given order otherwise" do
      expect(described_class.prioritize(%w[fast mid slow other], { "slow" => 2, "mid" => 1 }))
        .to eq(%w[slow mid fast other])
    end
  end
end

RSpec.describe Saboteur::Engine::Scheduler, "neutral check" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subject_under_test) { subjects_in("class SchedulerTarget\n  def m(a)\n    a + 1\n  end\nend\n").first }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => ["t1"] } }, tests: ["t1"])
  end
  let(:candidates) { Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics) }

  def schedule_with(neutral)
    runner = instance_double(Saboteur::Execution::Runner)
    allow(runner).to receive(:run).and_return(neutral)
    scheduler = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                    reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics)
    allow(scheduler).to receive(:load_problem).and_return(nil)
    scheduler.call(subject_under_test, candidates.for(subject_under_test))
  end

  def outcome(status, message = nil)
    Saboteur::Execution::Runner::Outcome.new(status: status, runtime: 1.0, message: message)
  end

  it "skips every mutant as a baseline failure when the unchanged method fails its tests" do
    expect(schedule_with(outcome(:killed)).map(&:reason).uniq).to eq(["baseline failure"])
  end

  it "says baseline timeout, not failure, when the unchanged method's tests are too slow" do
    expect(schedule_with(outcome(:timeout, "exceeded 300 s")).map(&:reason).uniq).to eq(["baseline timeout"])
  end
end
