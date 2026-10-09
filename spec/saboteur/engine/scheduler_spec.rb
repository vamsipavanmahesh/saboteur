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

RSpec.describe Saboteur::Engine::Scheduler, "coarse stop" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }

  def results_for(source)
    subject = subjects_in(source).first
    lines = (subject.start_line..subject.end_line).to_h { |line| [line, ["t1"]] }
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => lines }, tests: ["t1"])
    runner = instance_double(Saboteur::Execution::Runner)
    allow(runner).to receive(:run).and_return(Saboteur::Execution::Runner::Outcome.new(status: :survived, runtime: 0.1))
    scheduler = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                    reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics)
    allow(scheduler).to receive(:load_problem).and_return(nil)
    candidates = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics)
    scheduler.call(subject, candidates.for(subject))
  end

  it "skips fine mutants when a coarse mutant survives in a plain method" do
    reasons = results_for("class K\n  def m(a)\n    b = a + 1\n    b * 2\n  end\nend\n").map(&:reason)
    expect(reasons).to include("coarse mutant survived")
  end

  it "still runs fine mutants when the method has a rescue: the rescue may return what fine mutants expose" do
    reasons = results_for("class K\n  def m(a)\n    b = a + 1\n    b * 2\n  rescue ArgumentError\n    0\n  end\nend\n")
              .map(&:reason)
    expect(reasons).not_to include("coarse mutant survived")
  end
end
