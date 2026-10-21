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

  it "starts no CI workflow command from hostile text in a warning (#834)" do
    diagnostics.warn("x\n::error::injected")
    diagnostics.warn("see ##[error]y")
    expect(diagnostics.warnings).to eq(["x\n\\x3a:error::injected", "see ##\\x5berror]y"])
  end

  it "freezes copies of the generation and omission names, not the caller's strings" do
    file = +"a.rb"
    id = +"A#m"
    subject = instance_double(Saboteur::Subject, file: file, id: id)
    diagnostics.record_generation(subject, source: "subject", reason: "empty_generation")
    diagnostics.record_omission(subject, count: 2, limit: 1)
    expect([file.frozen?, id.frozen?]).to eq([false, false])
    expect([diagnostics.generation_events.first.file, diagnostics.omissions.first.subject]).to all(be_frozen)
  end

  it "stores a generation event as frozen strings, turning a symbol source into its name" do
    subject = instance_double(Saboteur::Subject, file: "a.rb", id: "A#m")
    diagnostics.record_generation(subject, source: :builtin, operator: :comparison, reason: "empty_generation")
    event = diagnostics.generation_events.first
    expect(event.to_h.values).to eq(["a.rb", "A#m", "builtin", "comparison", "empty_generation"])
    expect(event.to_h.values).to all(be_frozen)
    diagnostics.record_generation(subject, source: "subject", reason: "empty_generation")
    expect(diagnostics.generation_events.last.operator).to be_nil
  end

  it "flushes each plain progress mark before any progress file exists" do
    allow(err).to receive(:flush).and_call_original
    diagnostics.progress(instance_double(Saboteur::MutantResult, status: :killed))
    expect(err).to have_received(:flush).once
  end

  it "reports the count over the total without a percentage while the total is zero" do
    diagnostics.start_progress(0)
    expect(diagnostics.progress_summary(3)).to eq("3/0")
    diagnostics.finish_progress
  end

  describe "progress summary with a known total" do
    before do
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 106.0)
      diagnostics.start_progress(3)
    end

    after { diagnostics.finish_progress }

    it "floors the percentage and pads the estimate's seconds to two digits" do
      expect(diagnostics.progress_summary(2)).to eq("2/3 (66%) eta 0m03s")
    end

    it "rounds the estimate to the nearest second" do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(105.0)
      expect(diagnostics.progress_summary(2)).to end_with("eta 0m03s")
    end

    it "rounds a fractional estimate down when it is under half a second" do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(104.8)
      expect(diagnostics.progress_summary(2)).to end_with("eta 0m02s")
    end

    it "gives no estimate before the first mutant, at the total or past it" do
      expect(diagnostics.progress_summary(0)).to eq("0/3 (0%)")
      expect(diagnostics.progress_summary(3)).to eq("3/3 (100%)")
      expect(diagnostics.progress_summary(4)).to eq("4/3 (133%)")
    end
  end

  it "prints the progress legend on a pipe only, never on a terminal" do
    tty = StringIO.new
    allow(tty).to receive(:tty?).and_return(true)
    on_tty = described_class.new(tty)
    on_tty.start_progress(1)
    expect(tty.string).not_to include("saboteur: progress")
    on_tty.finish_progress

    diagnostics.start_progress(1)
    expect(err.string).to include("saboteur: progress . killed  S survived  T timeout  L resource limit  E error")
    diagnostics.finish_progress
  end

  it "prints marks without a contract token plain even when colour is on" do
    palette = Saboteur::Reporter::Palette.new(enabled: true)
    coloured = described_class.new(err, palette: palette)
    coloured.start_progress(2)
    coloured.progress(instance_double(Saboteur::MutantResult, status: :resource_limit))
    coloured.progress(instance_double(Saboteur::MutantResult, status: :mystery))
    expect(err.string).to include("L?")
    coloured.finish_progress
  end

  it "flushes after every mark once the progress file exists" do
    diagnostics.start_progress(10)
    allow(err).to receive(:flush).and_call_original
    diagnostics.progress(instance_double(Saboteur::MutantResult, status: :killed))
    expect(err).to have_received(:flush).once
    diagnostics.finish_progress
  end

  it "ends a CI progress line with the count, percentage and estimate every 50 mutants" do
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 110.0)
    diagnostics.start_progress(100)
    50.times { diagnostics.progress(instance_double(Saboteur::MutantResult, status: :killed)) }
    expect(err.string.lines.last).to eq("#{'.' * 50} 50/100 (50%) eta 0m10s\n")
    diagnostics.finish_progress
  end

  it "keeps a warning's own detail lines" do
    diagnostics.warn("fix it\n  the cause")
    expect(diagnostics.warnings).to eq(["fix it\n  the cause"])
  end

  it "does not escape twice text a site already made safe (#834)" do
    once = Saboteur::Text.display_safe("x\n::error::injected")
    diagnostics.warn("fix #{once}")
    expect(diagnostics.warnings).to eq(["fix x\\x0a::error::injected"])
  end

  it "escapes a noted message on stderr, including the announced one" do
    diagnostics.inform("note\n::warning::injected")
    diagnostics.announce("a\n::error::b")
    expect(err.string).to eq("saboteur: note\n\\x3a:warning::injected\nsaboteur: a\n\\x3a:error::b\n")
    expect(diagnostics.warnings).to eq(["a\n\\x3a:error::b"])
  end

  it "escapes warnings added in a batch, such as the ignore file's or a child's (#834)" do
    expect(diagnostics.add_warnings(["stale key a\n::error::x", "fine"])).to be_nil
    expect(diagnostics.warnings).to eq(["stale key a\n\\x3a:error::x", "fine"])
  end

  it "records the announced message as the same text it stored, so it prints once (#605)" do
    diagnostics.announce("a\n::error::b")
    expect(diagnostics.live_announced).to eq(diagnostics.warnings)
  end

  it "prints one mark per executed mutant" do
    %i[killed survived timeout error].each { |status| diagnostics.progress(instance_double(Saboteur::MutantResult, status:)) }
    expect(err.string).to eq(".STE")
  end

  it "records a repeated discovery failure once" do
    2.times { diagnostics.record_discovery_failure("/r/a.rb", reason: "unreadable") }
    diagnostics.record_discovery_failure("/r/b.rb", reason: "unreadable")
    expect(diagnostics.discovery_failures.map(&:file)).to eq(["/r/a.rb", "/r/b.rb"])
  end

  it "freezes the recorded failure strings without freezing the caller's" do
    file = +"a.rb"
    reason = +"unreadable"
    diagnostics.record_discovery_failure(file, reason: reason)
    failure = diagnostics.discovery_failures.first
    expect([failure.file, failure.reason]).to all(be_frozen)
    expect([file, reason]).to all(satisfy { |value| !value.frozen? })
  end

  it "stringifies the file and reason before storing them" do
    diagnostics.record_discovery_failure(Pathname.new("/r/a.rb"), reason: :unreadable)
    failure = diagnostics.discovery_failures.first
    expect([failure.file, failure.reason]).to eq(["/r/a.rb", "unreadable"])
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

  it "prints no subject line for an empty result set" do
    described_class.new(err, verbose: true).subject_progress(subject, [])
    expect(err.string).to eq("")
  end

  it "marks an unlisted status with a question mark" do
    described_class.new(err, verbose: true).subject_progress(subject, [Struct.new(:status).new(:mystery)])
    expect(err.string).to include("#{subject.id}  ?")
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

  it "prints only the elapsed time when the log is empty" do
    expect(beat).to eq("saboteur: baseline check 1: 40 s elapsed\n")
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
