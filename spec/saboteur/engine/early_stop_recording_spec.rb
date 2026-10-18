# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::EarlyStopRecording do
  # max_duration announced before fail_fast could stop the run: the budget
  # stop wins the reported reason (#296).
  it "reports max_duration when the budget was announced before the failure stop (#296)" do
    recorder = Object.new.extend(described_class)
    recorder.instance_variable_set(:@budget_announced, true)
    expect(recorder.send(:run_early_stop_reason)).to eq("max_duration")
    recorder.instance_variable_set(:@budget_announced, false)
    expect(recorder.send(:run_early_stop_reason)).to eq("fail_fast")
  end

  it "keeps the whole plan count when distribution stops before remaining subjects (#654)" do
    engine = Saboteur::Engine.new(Saboteur::Config.new({}), err: StringIO.new)
    distribution = instance_double(Saboteur::Engine::Distribution, unreached: [person_subject],
                                                                   truncated: [[person_subject, 2]],
                                                                   unverified: [person_subject],
                                                                   memory_report: nil, run: [])
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    engine.send(:run_candidates, [person_subject, person_subject], [[1, 2], [3, 4, 5]], nil, nil, nil)
    stop = engine.instance_variable_get(:@early_stop)
    expect(stop.planned_mutants).to eq(5)
    expect(stop.unreached).to eq([person_subject.id])
    expect(stop.truncated).to eq([{ subject: person_subject.id, omitted: 2 }])
    expect(stop.unverified).to eq([person_subject.id])
  end
end
