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
end
