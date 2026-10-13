# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Diagnostics do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err) }

  it "collects warnings and counts invalid mutations" do
    diagnostics.warn("one")
    2.times { diagnostics.count_invalid_mutation }
    expect([diagnostics.warnings, diagnostics.invalid_mutations]).to eq([["one"], 2])
  end

  it "prints one mark per executed mutant" do
    %i[killed survived timeout error].each { |status| diagnostics.progress(instance_double(Saboteur::MutantResult, status:)) }
    expect(err.string).to eq(".STE")
  end

  it "prefixes messages for the user" do
    diagnostics.inform("building")
    expect(err.string).to eq("saboteur: building\n")
  end
end

RSpec.describe Saboteur::Engine::Diagnostics, "progress heartbeat" do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err) }

  # The supervisor's wait loop drives tick, so no thread is ever alive at
  # fork time.
  it "prints elapsed time only once the interval passed" do
    heartbeat = diagnostics.progress_heartbeat("long phase", interval: 0.05)
    heartbeat.tick
    expect(err.string).to eq("")
    sleep 0.06
    heartbeat.tick
    expect(err.string).to match(/long phase: 0 s elapsed/)
    heartbeat.tick
    expect(err.string.lines.size).to eq(1)
    sleep 0.06
    heartbeat.tick
    expect(err.string.lines.size).to eq(2)
  end

  # The gate is inclusive: an elapsed time of exactly the interval prints.
  it "prints when exactly the interval has elapsed" do
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 100.0, 130.0)
    heartbeat = diagnostics.progress_heartbeat("long phase", interval: 30)
    heartbeat.tick
    expect(err.string).to eq("")
    heartbeat.tick
    expect(err.string).to match(/long phase: 30 s elapsed/)
  end
end

RSpec.describe Saboteur::Engine::Diagnostics, "hazard suppressions (issue #102)" do
  it "counts each suppression and records a generation event" do
    diagnostics = described_class.new(StringIO.new)
    subject = subjects_in("class K\n  def m\n    1\n  end\nend\n").first
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: 20, end_byte: 21,
                                              replacement: "2")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "literal_number",
                                                      edits: [edit])
    expect { diagnostics.record_hazard_suppression(subject, mutation) }
      .to change { diagnostics.hazard_suppressions }.from(0).to(1)
    event = diagnostics.generation_events.last
    expect([event.source, event.operator, event.reason]).to eq(%w[hazard_guard literal_number hazardous])
  end
end
