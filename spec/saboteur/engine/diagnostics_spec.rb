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

RSpec.describe Saboteur::Engine::Diagnostics, "per-subject verbose lines" do
  let(:err) { StringIO.new }
  let(:subject) { Struct.new(:id).new("Lrs::ManualPaymentResolver#with_resolution_lock") }
  let(:results) { [Struct.new(:status).new(:killed), Struct.new(:status).new(:survived)] }

  it "prints one line per finished subject with its result marks when verbose" do
    diagnostics = described_class.new(err, verbose: true)
    diagnostics.subject_progress(subject, results)
    expect(err.string).to include("Lrs::ManualPaymentResolver#with_resolution_lock  .S")
  end

  it "stays silent without verbose" do
    described_class.new(err).subject_progress(subject, results)
    expect(err.string).to eq("")
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

RSpec.describe Saboteur::Engine::Diagnostics, "progress heartbeat with a watched log (issue #56)" do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err) }
  let(:log) { Tempfile.new("phase-log") }

  after { log.close! }

  def beat(elapsed: 40, written: nil)
    log.write(written) if written
    log.flush
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 100.0 + elapsed)
    heartbeat = diagnostics.progress_heartbeat("baseline check 1", interval: 30).watch(log.path)
    heartbeat.tick
    err.string
  end

  it "adds the count, the percentage and a time estimate from the last progress line" do
    out = beat(written: "25/100 examples finished\n50/100 examples finished\n")
    expect(out).to eq("saboteur: baseline check 1: 40 s elapsed, 50/100 examples (50 %), about 40 s left\n")
  end

  it "prints only the elapsed time while the log has no count" do
    expect(beat(written: "starting\n")).to eq("saboteur: baseline check 1: 40 s elapsed\n")
  end

  it "prints only the elapsed time when the log does not exist yet" do
    log.close!
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 140.0)
    heartbeat = diagnostics.progress_heartbeat("coverage", interval: 30).watch("/nonexistent/phase.log")
    heartbeat.tick
    expect(err.string).to eq("saboteur: coverage: 40 s elapsed\n")
  end

  it "gives no estimate when every example finished or none did" do
    expect(beat(written: "100/100 examples finished\n")).to end_with("100/100 examples (100 %)\n")
  end

  it "gives no estimate before the first example or past the total" do
    expect(beat(written: "0/100 examples finished\n")).to end_with("0/100 examples (0 %)\n")
    err.truncate(0)
    err.rewind
    log.truncate(0)
    log.rewind
    expect(beat(written: "150/100 examples finished\n")).to end_with("150/100 examples (150 %)\n")
  end

  it "ignores a zero total" do
    expect(beat(written: "0/0 examples finished\n")).to eq("saboteur: baseline check 1: 40 s elapsed\n")
  end

  it "reads the end of a long log" do
    out = beat(written: "#{'x' * 10_000}\n20/80 examples finished\n")
    expect(out).to include("20/80 examples (25 %), about 120 s left")
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
