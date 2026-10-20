# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Gates do
  def report(*statuses, root: nil)
    return report_of(*statuses.map { |status| result_for(status) }) unless root

    Saboteur::Report.new(results: statuses.map { |status| result_for(status) }, subjects: [person_subject],
                         wall_time: 1.0, root:, seed: 1,
                         operator_policy: Saboteur::Config.new({}).operator_policy)
  end

  describe "#failed? with record_cause: false" do
    let(:limit) { described_class.new("max_timeouts" => 0) }

    it "still prints the failed gate and returns true, but leaves the cause unset" do
      err = StringIO.new
      expect(limit.failed?(report(:timeout, :killed), err, record_cause: false)).to be(true)
      expect(err.string).to eq("saboteur: 1 timeout mutants, above --max-timeouts 0\n")
      expect(limit.cause).to be_nil
    end

    it "records the cause by default" do
      limit.failed?(report(:timeout, :killed), StringIO.new)
      expect(limit.cause).to eq("maxTimeouts")
    end
  end

  describe "matching results to score gates" do
    it "never reads the report root when there are no score gates" do
      gates = described_class.new("max_timeouts" => 1)
      missing = report(:killed, root: "/no/such/saboteur/root")
      expect(gates.send(:gate_matching, missing)).to eq([[], []])
    end

    it "matches and assigns a result to the gate whose pattern fits its file" do
      gates = described_class.new("score_gates" => [{ "pattern" => "person.rb", "min_score" => 50 }])
      matched, assigned = gates.send(:gate_matching, report(:killed))
      expect(matched.map(&:size)).to eq([1])
      expect(assigned.map(&:size)).to eq([1])
    end
  end
end
