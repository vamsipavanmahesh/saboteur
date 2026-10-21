# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Distribution, "fail fast" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:calls) { [] }
  let(:scheduler) do
    calls_seen = calls
    Class.new do
      define_method(:call) do |subject, _list|
        calls_seen << subject
        [subject]
      end
    end.new
  end

  def distribution(stop_after)
    described_class.new(jobs: 1, scheduler: scheduler, diagnostics: diagnostics, cache: nil, stop_after: stop_after)
  end

  it "stops before the next subject once the callable says so" do
    run = distribution(->(subject_results) { subject_results == [:b] })
    results = run.run(%i[a b c], [[1], [1], [1]])
    expect(calls).to eq(%i[a b])
    expect(results).to eq(%i[a b])
    expect(run.unreached).to eq([:c])
  end

  it "has no unreached subjects when the last subject triggers the stop, or nothing does" do
    last = distribution(->(subject_results) { subject_results == [:c] })
    last.run(%i[a b c], [[1], [1], [1]])
    expect(last.unreached).to eq([])
    plain = distribution(nil)
    plain.run(%i[a b], [[1], [1]])
    expect(plain.unreached).to eq([])
  end

  it "runs every subject without a stop condition" do
    distribution(nil).run(%i[a b c], [[1], [1], [1]])
    expect(calls).to eq(%i[a b c])
  end
end

RSpec.describe Saboteur::IgnoreList, "accepts?" do
  it "accepts only survivors listed by subject and digest" do
    result = result_for(:survived)
    list = described_class.new([described_class::Entry.new(subject: result.subject.id, mutation: result.digest,
                                                           reason: "equivalent")])
    expect(list.accepts?(result)).to be(true)
    expect(described_class.new([]).accepts?(result)).to be(false)
    expect(list.accepts?(result_for(:killed))).to be(false)
  end
end

RSpec.describe Saboteur::Config, "fail_fast" do
  it "refuses fail_fast with more than one job" do
    expect { described_class.load(root: Dir.pwd, overrides: { "fail_fast" => true, "jobs" => 2 }) }
      .to raise_error(Saboteur::ConfigError, /fail_fast needs jobs 1/)
  end
end

RSpec.describe Saboteur::Engine, "fail_fast with baseline evidence" do
  it "refuses, because evidence certifies the whole selection" do
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    config = Saboteur::Config.load(root: Dir.pwd, overrides: { "fail_fast" => true })
    expect { described_class.new(config, capture_evidence: true).call }
      .to raise_error(Saboteur::ConfigError, /fail_fast cannot be used with baseline evidence/)
  end
end

RSpec.describe Saboteur::Engine, "fail-fast check" do
  let(:err) { StringIO.new }
  let(:ignore_list) { instance_double(Saboteur::IgnoreList, accepts?: false) }

  def check_for(values)
    described_class.new(Saboteur::Config.new(values), err: err).send(:fail_fast_check, ignore_list)
  end

  it "is absent unless fail_fast is configured" do
    expect(check_for({})).to be_nil
  end

  it "stops, and says so, after a subject with an unaccepted survivor" do
    survivor = Struct.new(:survived?).new(true)
    expect(check_for("fail_fast" => true).call([survivor])).to be(true)
    expect(err.string).to include("--fail-fast: stopping after the first subject with a survivor")
  end

  it "keeps going when every survivor is accepted or none survived" do
    check = check_for("fail_fast" => true)
    expect(check.call([Struct.new(:survived?).new(false)])).to be(false)
    allow(ignore_list).to receive(:accepts?).and_return(true)
    expect(check.call([Struct.new(:survived?).new(true)])).to be(false)
    expect(err.string).to be_empty
  end

  it "stops when any result of a mixed batch survives unaccepted" do
    check = check_for("fail_fast" => true)
    results = [Struct.new(:survived?).new(false), Struct.new(:survived?).new(true)]
    expect(check.call(results)).to be(true)
    expect(err.string).to include("--fail-fast: stopping after the first subject with a survivor")
  end
end

RSpec.describe Saboteur::Engine, "early stop wiring" do
  let(:err) { StringIO.new }

  def engine(values = {}, **options)
    described_class.new(Saboteur::Config.new(values), err: err, **options)
  end

  def person
    subjects_in("class Person\n  def adult?; @age >= 18; end\nend\n", name: "person.rb").first
  end

  it "marks the report as a matrix run only when matrix is configured" do
    plain = engine.send(:build_report, [], [], nil, 0)
    matrix = engine({ "matrix" => true }).send(:build_report, [], [], nil, 0)
    expect([plain.matrix?, matrix.matrix?]).to eq([false, true])
  end

  def distribution_double(unreached: [], truncated: [], unverified: [])
    instance_double(Saboteur::Engine::Distribution, memory_report: nil, unreached: unreached, truncated: truncated,
                                                    unverified: unverified)
  end

  it "records the subjects a stop left unrun, and nothing when none were left" do
    stopped = engine
    stopped.send(:record_early_stop, distribution_double(unreached: [person]))
    report = stopped.send(:build_report, [], [], nil, 0)
    expect(report.early_stop)
      .to eq(Saboteur::EarlyStop.new(reason: "fail_fast", unreached: ["Person#adult?"], truncated: [], unverified: []))
    whole = engine
    whole.send(:record_early_stop, distribution_double(unreached: []))
    expect(whole.send(:build_report, [], [], nil, 0).early_stop).to be_nil
  end

  it "carries the suppressed hazard count into the report next to the early stop" do
    run = engine
    subject = person
    at = subject.file_source.index(">=")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2, replacement: ">")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits: [edit])
    3.times { run.instance_variable_get(:@diagnostics).record_hazard_suppression(subject, mutation) }
    run.send(:record_early_stop, distribution_double(unreached: [person]))
    report = run.send(:build_report, [], [], nil, 0)
    expect([report.hazard_suppressions, report.early_stop&.reason]).to eq([3, "fail_fast"])
  end

  it "refuses baseline evidence only when fail_fast and capture_evidence are both on" do
    expect { engine({ "fail_fast" => true }).send(:refuse_fail_fast_evidence) }.not_to raise_error
    expect { engine({ "fail_fast" => false }, capture_evidence: true).send(:refuse_fail_fast_evidence) }
      .not_to raise_error
    expect { engine({ "fail_fast" => true }, capture_evidence: true).send(:refuse_fail_fast_evidence) }
      .to raise_error(Saboteur::ConfigError, /baseline evidence/)
  end

  it "announces the candidate total, hands Distribution both the canary and the stop check, and records the stop" do
    run = engine({ "fail_fast" => true })
    diagnostics = run.instance_variable_get(:@diagnostics)
    allow(diagnostics).to receive(:start_progress)
    allow(run).to receive_messages(canary_check: :canary, fail_fast_check: :stopper)
    distribution = instance_double(Saboteur::Engine::Distribution, memory_report: nil, run: [:result],
                                                                   unreached: [person],
                                                                   truncated: [], unverified: [])
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    expect(run.send(:run_candidates, [person], [[1, 2], [3]], :scheduler, nil, :ignores)).to eq([:result])
    expect(diagnostics).to have_received(:start_progress).with(3)
    expect(Saboteur::Engine::Distribution).to have_received(:new)
      .with(hash_including(after_subject: kind_of(Proc), stop_after: kind_of(Proc), scheduler: :scheduler))
    expect(run.send(:build_report, [], [], nil, 0).early_stop.unreached).to eq(["Person#adult?"])
  end
end

RSpec.describe Saboteur::Engine::Distribution, "without parallelism" do
  it "runs a zero-job distribution serially" do
    scheduler = Class.new { def call(subject, _list) = [subject] }.new
    run = described_class.new(jobs: 0, scheduler: scheduler, diagnostics: nil, cache: nil)
    expect(run.run(%i[a b], [[1], [1]])).to eq(%i[a b])
  end

  it "calls the after-subject watcher once per subject, before the stop check" do
    order = []
    scheduler = Class.new { def call(subject, _list) = [subject] }.new
    run = described_class.new(jobs: 1, scheduler: scheduler, diagnostics: nil, cache: nil,
                              after_subject: ->(subject, _results) { order << [:watch, subject] },
                              stop_after: ->(results) { order << [:stop, results.first] and false })
    run.run(%i[a b], [[1], [1]])
    expect(order).to eq([%i[watch a], %i[stop a], %i[watch b], %i[stop b]])
  end
end

RSpec.describe Saboteur::Config, "fail_fast with a single job" do
  def check(jobs)
    described_class.new({ "fail_fast" => true, "jobs" => jobs }).send(:validate_fail_fast!)
  end

  it "accepts one job and refuses two" do
    expect { check(1) }.not_to raise_error
    expect { check(2) }.to raise_error(Saboteur::ConfigError, /fail_fast needs jobs 1/)
  end
end
