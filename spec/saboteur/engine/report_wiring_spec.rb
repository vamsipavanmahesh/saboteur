# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "report wiring" do
  it "flows the run's discovery failures into the report" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    engine.instance_variable_get(:@diagnostics).record_discovery_failure("/r/a.rb", reason: "unreadable")
    report = engine.send(:build_report, [], [], nil, engine.send(:monotonic))
    expect(report.discovery_failures.map(&:reason)).to eq(["unreadable"])
  end
end
