# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::Distribution do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }

  # The run's peak-memory record for the JSON report (#202): nil when the
  # platform measured nothing, otherwise the sorted worker rows and the
  # supervisor's own peak.
  describe "#memory_report (#202)" do
    def memory_distribution
      described_class.new(jobs: 2, scheduler: ->(_subject, _list) { [] }, diagnostics:, cache: nil)
    end

    it "is nil when neither the workers nor the supervisor were measured" do
      allow(Saboteur::Execution::PeakMemory).to receive(:peak_mb).and_return(nil)
      expect(memory_distribution.memory_report).to be_nil
    end

    it "lists each worker's peak sorted by worker number" do
      distribution = memory_distribution
      peaks = { 2 => 300.0, 1 => 200.5 }
      distribution.instance_variable_set(:@pool, instance_double(Saboteur::Execution::WorkerPool,
                                                                 worker_peaks: peaks))
      allow(Saboteur::Execution::PeakMemory).to receive(:peak_mb).and_return(nil)
      expect(distribution.memory_report)
        .to eq(workers: [{ worker: 1, peakMb: 200.5 }, { worker: 2, peakMb: 300.0 }])
    end

    it "keeps the supervisor's own peak beside an empty worker list" do
      allow(Saboteur::Execution::PeakMemory).to receive(:peak_mb).and_return(30.5)
      expect(memory_distribution.memory_report).to eq(workers: [], supervisorPeakMb: 30.5)
    end
  end

  it "invokes after_subject with each subject's results in serial" do
    scheduler = ->(subject, list) { [subject, list] }
    seen = []
    distribution = described_class.new(jobs: 1, scheduler:, diagnostics:, cache: nil,
                                       after_subject: ->(subject, results) { seen << [subject, results] })
    distribution.run(%i[a b], [["la"], ["lb"]])
    expect(seen).to eq([[:a, [:a, ["la"]]], [:b, [:b, ["lb"]]]])
  end

  it "flags a serial subject when any result is unverified, and records the shortfall (#296)" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "x"),
           Saboteur::MutantResult.new(subject:, mutation:, status: :unverified, mutated_source: "x")]
    scheduler = ->(_subject, _list) { row }
    distribution = described_class.new(jobs: 1, scheduler:, diagnostics:, cache: nil)
    distribution.run([subject], [[[fixture_mutation(subject), "a"], [fixture_mutation(subject), "b"],
                                  [fixture_mutation(subject), "c"]]])
    expect(distribution.unverified).to eq([subject])
    expect(distribution.truncated).to eq([[subject, 1]])
  end

  it "leaves the serial unverified and truncated lists empty when nothing was cut (#296)" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "x")]
    scheduler = ->(_subject, _list) { row }
    distribution = described_class.new(jobs: 1, scheduler:, diagnostics:, cache: nil)
    distribution.run([subject], [[[fixture_mutation(subject), "a"]]])
    expect(distribution.unverified).to eq([])
    expect(distribution.truncated).to eq([])
  end

  it "runs serial without an after_subject callback" do
    scheduler = ->(subject, _list) { [subject] }
    distribution = described_class.new(jobs: 1, scheduler:, diagnostics:, cache: nil)
    expect(distribution.run(%i[a], [[]])).to eq([:a])
  end

  it "runs after_subject as each row arrives in parallel and stops the queue when it raises" do
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: subject.file_source.index("1"),
                                              end_byte: subject.file_source.index("1") + 1, replacement: "2")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "x")]
    scheduler = ->(_subject, _list) { row }
    trips = []
    after = lambda do |seen_subject, results|
      trips << [seen_subject.id, results.map(&:status)]
      raise Saboteur::CanaryTripped, "canary: trip"
    end
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil, after_subject: after)
    lists = [[[mutation, "text"]], [[mutation, "text"]], [[mutation, "text"]]]
    expect { distribution.run([subject, subject, subject], lists) }
      .to raise_error(Saboteur::Error, "canary: trip")
    expect(trips.size).to be < 3
    expect(trips.first).to eq(["K#m", [:killed]])
  end

  it "runs parallel without an after_subject callback" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "text")]
    scheduler = ->(_subject, _list) { row }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    expect(distribution.run([subject], [[[mutation, "text"]]]).map(&:status)).to eq([:killed])
  end

  it "marks a subject whose fresh kills the budget left unchecked in serial (#296)" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :unverified, mutated_source: "text",
                                      reason: "verdict check skipped: the --max-duration budget is spent")]
    distribution = described_class.new(jobs: 1, scheduler: ->(_s, _l) { row }, diagnostics:, cache: nil)
    distribution.run([subject], [[[mutation, "text"]]])
    expect(distribution.unverified).to eq([subject])
    expect(distribution.truncated).to eq([])
  end

  # A worker row can mix unverified results with tested ones; any? flags the
  # subject, all? would miss the mix (#296).
  it "flags a subject when only some of its results are unverified (#296)" do
    distribution = described_class.new(jobs: 2, scheduler: nil, diagnostics:, cache: nil)
    rows = [{ "results" => [{ "status" => "unverified" }, { "status" => "killed" }] }]
    distribution.send(:record_unreached, rows, %i[a], [[1, 2]])
    expect(distribution.unverified).to eq([:a])
  end

  it "does not call a flaky-check disagreement a budget shortfall, serial or in worker rows (#1167)" do
    flaky = "#{Saboteur::MutantResult::FLAKY_PREFIX}: first survived, then killed on a reordered confirmation run"
    subject = fixture_subject
    row = [Saboteur::MutantResult.new(subject:, mutation: fixture_mutation(subject), status: :unverified,
                                      mutated_source: "x", reason: flaky)]
    serial = described_class.new(jobs: 1, scheduler: ->(_subject, _list) { row }, diagnostics:, cache: nil)
    serial.run([subject], [[[fixture_mutation(subject), "a"]]])
    expect(serial.unverified).to eq([])
    parallel = described_class.new(jobs: 2, scheduler: nil, diagnostics:, cache: nil)
    parallel.send(:record_unreached, [{ "results" => [{ "status" => "unverified", "reason" => flaky }] },
                                      { "results" => [{ "status" => "unverified", "reason" => "budget" }] }],
                  %i[a b], [[1], [1]])
    expect(parallel.unverified).to eq([:b])
  end

  it "marks unverified subjects from worker rows in parallel (#296)" do
    distribution = described_class.new(jobs: 2, scheduler: nil, diagnostics:, cache: nil)
    rows = [{ "results" => [{ "status" => "unverified" }] }, { "results" => [{ "status" => "killed" }] }]
    distribution.send(:record_unreached, rows, %i[a b], [[1], [1]])
    expect(distribution.unverified).to eq([:a])
    expect(distribution.unreached).to eq([])
    expect(distribution.truncated).to eq([])
  end

  it "accounts a deadline-truncated subject's omitted candidates in serial (#245)" do
    scheduler = ->(_subject, list) { [list.first] } # the deadline broke the loop after one
    distribution = described_class.new(jobs: 1, scheduler:, diagnostics:, cache: nil)
    expect(distribution.run(%i[a], [[1, 2, 3]])).to eq([1])
    expect(distribution.unreached).to eq([])
    expect(distribution.truncated).to eq([[:a, 2]])
  end

  it "accounts a deadline-truncated subject's omitted candidates in parallel (#245)" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "text")]
    scheduler = ->(_subject, _list) { row } # one result for three candidates
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    lists = [[[mutation, "t1"], [mutation, "t2"], [mutation, "t3"]]]
    distribution.run([subject], lists)
    expect(distribution.unreached).to eq([])
    expect(distribution.truncated).to eq([[subject, 2]])
  end

  def fixture_subject
    subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
  end

  def fixture_mutation(subject)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: subject.file_source.index("1"),
                                              end_byte: subject.file_source.index("1") + 1, replacement: "2")
    Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
  end

  it "propagates a worker's tool error as a run-aborting error, not per-mutant errors" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    scheduler = ->(_subject, _list) { raise Saboteur::Error, "cannot open the child log /x/child-1-1.log (Errno::ENOENT)" }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    expect { distribution.run([subject], [[[mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, /cannot open the child log/)
  end

  it "aborts as the tool-error row arrives, before the pool hands out the remaining work" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    # A file marker, not an array: the scheduler runs inside forked workers,
    # so only the filesystem carries the record back into the parent.
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "scheduled")
      scheduler = lambda do |_subject, _list|
        File.open(marker, "a") { |file| file.puts("ran") }
        raise Saboteur::Error, "the child log /x/child-1-1.log vanished mid-run"
      end
      distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil,
                                         after_subject: ->(_s, _r) {})
      lists = [[[mutation, "text"]], [[mutation, "text"]], [[mutation, "text"]]]
      expect { distribution.run([subject, subject, subject], lists) }
        .to raise_error(Saboteur::Error, /vanished mid-run/)
      # The pool assigns the first two subjects up front and the third only
      # after a row arrives - and the arriving tool error raises first, so it
      # is never scheduled. A fast abort can stop the second worker before it
      # records, so one or two entries are valid; three never are.
      expect(File.readlines(marker).size).to be_between(1, 2)
    end
  end

  it "aborts a row the callback path missed: a tool error still stops the rebuild" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    pool = instance_double(Saboteur::Execution::WorkerPool)
    allow(Saboteur::Execution::WorkerPool).to receive(:new).and_return(pool)
    allow(pool).to receive(:map).and_return([{ "tool_error" => "the child log /x/c-1.log vanished mid-run" }])
    distribution = described_class.new(jobs: 2, scheduler: ->(_s, _l) { [] }, diagnostics:, cache: nil)
    expect { distribution.run([subject], [[[mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, /vanished mid-run/)
  end

  # A wiped log dir hits every worker: a bystander whose current job ran no
  # mutant reports "an unknown mutant", and it can land before the culprit's
  # own report (macOS CI on #285). The abort must wait for in-flight workers
  # and prefer the report that names its mutant.
  it "prefers the tool error that names its mutant when a bystander's report lands first" do
    bystander = fixture_subject
    culprit = fixture_subject
    mutation = fixture_mutation(culprit)
    scheduler = lambda do |subject, _list|
      if subject.equal?(bystander)
        raise Saboteur::Execution::Runner::LogVanished,
              "the child log /x/b.log vanished mid-run - the mutant that just ran, an unknown mutant, " \
              "is the likely cause"
      end

      sleep 0.2
      raise Saboteur::Execution::Runner::LogVanished.new(
        "the child log /x/c.log vanished mid-run - the mutant that just ran, 0123456789abcdef, is the likely cause",
        culprit_digest: "0123456789abcdef"
      )
    end
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    expect { distribution.run([bystander, culprit], [[[mutation, "text"]], [[mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, /0123456789abcdef/)
  end

  # Neither report names a mutant: the abort keeps the earliest detection.
  it "raises the first bare tool error when no report names a mutant" do
    first = fixture_subject
    second = fixture_subject
    mutation = fixture_mutation(first)
    scheduler = lambda do |subject, _list|
      sleep 0.2 if subject.equal?(second)
      raise Saboteur::Error, (subject.equal?(first) ? "first report: log dir gone" : "second report: log dir gone")
    end
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    expect { distribution.run([first, second], [[[mutation, "text"]], [[mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, "first report: log dir gone")
  end

  # Biggest subjects first (#283 review): the pool gets each subject's
  # candidate count as its weight.
  it "hands the pool each subject's candidate count as its weight" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    pool = instance_double(Saboteur::Execution::WorkerPool)
    allow(Saboteur::Execution::WorkerPool).to receive(:new).and_return(pool)
    expect(pool).to receive(:map).with([0, 1], weights: [1, 2]).and_return([{ "tool_error" => "stop here" }, nil])
    distribution = described_class.new(jobs: 2, scheduler: ->(_s, _l) { [] }, diagnostics:, cache: nil)
    expect { distribution.run([subject, subject], [[[mutation, "text"]], [[mutation, "text"], [mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, "stop here")
  end

  # The hazard report keeps winning over a bare log-loss report (#283): a
  # canary trip aborts the run even when the bare report arrived first.
  it "lets a canary trip win over an earlier bare log-loss report" do
    first = fixture_subject
    second = fixture_subject
    mutation = fixture_mutation(first)
    scheduler = lambda do |subject, _list|
      if subject.equal?(first)
        raise Saboteur::Execution::Runner::LogVanished,
              "the child log /x/b.log vanished mid-run - the mutant that just ran, an unknown mutant, " \
              "is the likely cause"
      end
      sleep 0.2
      raise Saboteur::CanaryTripped,
            "canary: 1 watched file(s) vanished from the working tree while mutants ran (first: lib/a.rb). " \
            "The mutant that just ran, fedcba9876543210, is the likely cause."
    end
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    expect { distribution.run([first, second], [[[mutation, "text"]], [[mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, /canary: 1 watched file.*fedcba9876543210/m)
  end

  # Attribution quality beats report type (#285 review): a report that
  # names its mutant outranks a subject-last canary trip, whose "most
  # recent mutant" is only the likely cause.
  it "prefers a report that names its mutant over a subject-last canary trip" do
    canary_subject = fixture_subject
    culprit = fixture_subject
    mutation = fixture_mutation(culprit)
    scheduler = lambda do |subject, _list|
      if subject.equal?(canary_subject)
        raise Saboteur::CanaryTripped,
              "canary: 1 watched file(s) vanished from the working tree while mutants ran (first: lib/a.rb). " \
              "The most recent mutant, fedcba9876543210, is the likely cause."
      end
      sleep 0.2
      raise Saboteur::Execution::Runner::LogVanished.new(
        "the child log /x/c.log vanished mid-run - the mutant that just ran, 0123456789abcdef, is the likely cause",
        culprit_digest: "0123456789abcdef"
      )
    end
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    expect { distribution.run([canary_subject, culprit], [[[mutation, "text"]], [[mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, /0123456789abcdef/)
  end

  # A neutral job's canary trip names no mutant ("an unknown mutant" is
  # display text, not metadata): it must not outrank a delayed report
  # carrying a real digest (#285 review).
  it "prefers a delayed real digest over an unknown-mutant canary trip" do
    canary_subject = fixture_subject
    culprit = fixture_subject
    mutation = fixture_mutation(culprit)
    scheduler = lambda do |subject, _list|
      if subject.equal?(canary_subject)
        raise Saboteur::CanaryTripped,
              "canary: 1 watched file(s) vanished from the working tree while mutants ran (first: lib/a.rb)."
      end
      sleep 0.2
      raise Saboteur::Execution::Runner::LogVanished.new(
        "the child log /x/c.log vanished mid-run - the mutant that just ran, 0123456789abcdef, is the likely cause",
        culprit_digest: "0123456789abcdef"
      )
    end
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    expect { distribution.run([canary_subject, culprit], [[[mutation, "text"]], [[mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, /0123456789abcdef/)
  end

  # A canary trip from the subject callback (a normal row's end-of-subject
  # check) must not escape the pool and override a collected report that
  # names the real culprit: it folds into the same record + halt + prefer
  # path as a worker's own report (#285 review).
  it "folds a callback canary trip into the preferred reports instead of overriding a culprit" do
    bystander = fixture_subject
    culprit = fixture_subject
    mutation = fixture_mutation(culprit)
    bystander_mutation = fixture_mutation(bystander)
    scheduler = lambda do |subject, _list|
      unless subject.equal?(culprit)
        return [Saboteur::MutantResult.new(subject:, mutation: bystander_mutation, status: :killed,
                                           mutated_source: "text")]
      end

      sleep 0.2
      raise Saboteur::Execution::Runner::LogVanished.new(
        "the child log /x/c.log vanished mid-run - the mutant that just ran, 0123456789abcdef, is the likely cause",
        culprit_digest: "0123456789abcdef"
      )
    end
    after_subject = lambda do |_subject, _results|
      raise Saboteur::CanaryTripped,
            "canary: 1 watched file(s) vanished from the working tree while mutants ran (first: lib/a.rb). " \
            "The most recent mutant, fedcba9876543210, is the likely cause."
    end
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil, after_subject:)
    expect { distribution.run([bystander, culprit], [[[bystander_mutation, "text"]], [[mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, /0123456789abcdef/)
  end

  it "raises a folded callback canary trip when no report names a mutant" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "text")]
    scheduler = ->(_subject, _list) { row }
    after_subject = ->(_subject, _results) { raise Saboteur::CanaryTripped, "canary: trip at subject end" }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil, after_subject:)
    expect { distribution.run([subject], [[[mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, "canary: trip at subject end")
  end

  # A wedged worker must not stall a safety abort: the pool stops waiting
  # at the drain deadline and the abort raises the best report collected
  # by then (#285 review).
  it "stops waiting for a wedged worker at the drain deadline and raises the collected report" do
    wedged = fixture_subject
    reporter = fixture_subject
    mutation = fixture_mutation(reporter)
    scheduler = lambda do |subject, _list|
      sleep 3600 if subject.equal?(wedged)
      raise Saboteur::Error, "the child log /x/r.log vanished mid-run"
    end
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil, drain_timeout: 0.2)
    expect { distribution.run([wedged, reporter], [[[mutation, "text"]], [[mutation, "text"]]]) }
      .to raise_error(Saboteur::Error, "the child log /x/r.log vanished mid-run")
  end

  it "escapes the warnings a worker row carries into the diagnostics (#834)" do
    distribution = described_class.new(jobs: 2, scheduler: ->(_subject, _list) { [] }, diagnostics:, cache: nil)
    allow(distribution).to receive(:decode).and_return([])
    distribution.send(:rebuild, { "warnings" => ["x\n::error::injected"] }, fixture_subject, [])
    expect(diagnostics.warnings).to eq(["x\n\\x3a:error::injected"])
  end

  it "warns and returns error results when a worker row carries an error" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    scheduler = ->(_subject, _list) { raise "worker exploded" }
    arrived = []
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil,
                                       after_subject: lambda { |seen, results|
                                         arrived << [seen.id, results.map(&:status), results.map(&:reason)]
                                       })
    results = distribution.run([subject], [[[mutation, "text"]]])
    expect(results.map(&:status)).to eq([:error])
    expect(results.first.reason).to include("worker exploded")
    expect(diagnostics.warnings.join).to include("K#m: its mutants are reported as errors\n  " \
                                                 "RuntimeError: worker exploded")
    expect(arrived).to eq([["K#m", [:error], ["RuntimeError: worker exploded"]]])
  end

  it "starts the pool with the configured jobs, on_start and arrival callback" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "text")]
    scheduler = ->(_subject, _list) { row }
    starter = ->(_worker) {}
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil, on_start: starter,
                                       after_subject: ->(_seen, _results) {})
    expect(Saboteur::Execution::WorkerPool).to receive(:new)
      .with(jobs: 2, on_start: starter, on_result: kind_of(Proc), drain_timeout: 30).and_call_original
    distribution.run([subject], [[[mutation, "text"]]])
  end

  it "round-trips every result field through the worker row encoding" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "text",
                                      reason: "failed assertion", runtime: 0.25, killed_by: ["spec one"],
                                      covered_by: ["0"], kill_cause: "assertion", reused: false, rejected_kill: true)]
    scheduler = ->(_subject, _list) { row }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    result = distribution.run([subject], [[[mutation, "text"]]]).first
    expect(result.status).to eq(:killed)
    expect(result.reason).to eq("failed assertion")
    expect(result.runtime).to eq(0.25)
    expect(result.killed_by).to eq(["spec one"])
    expect(result.covered_by).to eq(["0"])
    expect(result.kill_cause).to eq("assertion")
    expect(result.reused?).to be(false)
    expect(result.rejected_kill?).to be(true)
    expect(result.mutated_source).to eq("text")
  end

  it "reads a worker row without a rejected_kill field as not rejected" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    row = { "results" => [{ "position" => 0, "status" => "killed", "reason" => nil, "runtime" => 0.1,
                            "killed_by" => ["t"], "covered_by" => ["t"], "kill_cause" => "assertion",
                            "reused" => false, "executed" => ["t"] }] }
    distribution = described_class.new(jobs: 2, scheduler: ->(_s, _l) { [] }, diagnostics:, cache: nil)
    result = distribution.send(:decode, row, subject, [[mutation, "text"]]).first
    expect(result.rejected_kill?).to be(false)
  end

  it "records fresh results in the cache and skips reused ones" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    fresh = Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "text")
    reused = Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "text", reused: true)
    scheduler = ->(_subject, _list) { [fresh, reused] }
    recorded = []
    cache = instance_double(Saboteur::Engine::ResultCache)
    allow(cache).to receive(:record) { |result| recorded << result }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache:)
    distribution.run([subject], [[[mutation, "text"], [mutation, "text"]]])
    expect(recorded.size).to eq(1)
    expect(recorded.first.status).to eq(:killed)
    expect(recorded.first.reused?).to be(false)
  end

  it "uses the worker pool when jobs is above one" do
    scheduler = ->(subject, _list) { [subject] }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    allow(Saboteur::Execution::WorkerPool).to receive(:new).and_raise(Saboteur::Error, "pool started")
    expect { distribution.run(%i[a], [[]]) }.to raise_error(Saboteur::Error, "pool started")
  end
end

RSpec.describe Saboteur::Engine::Distribution, "truncation accounting boundaries (#296)" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }

  def account(rows, lists)
    distribution = described_class.new(jobs: 2, scheduler: nil, diagnostics:, cache: nil)
    distribution.send(:record_unreached, rows, %i[a b c], lists)
    distribution
  end

  it "resets the accounting between runs" do
    distribution = described_class.new(jobs: 2, scheduler: nil, diagnostics:, cache: nil)
    dirty = [{ "results" => [{ "status" => "unverified" }] }, nil]
    distribution.send(:record_unreached, dirty, %i[a b], [[1, 2], [1]])
    expect(distribution.truncated).not_to be_empty
    expect(distribution.unverified).not_to be_empty
    expect(distribution.unreached).not_to be_empty
    distribution.send(:record_unreached, [{ "results" => [{ "status" => "killed" }] }], %i[a], [[1]])
    expect(distribution.unreached).to eq([])
    expect(distribution.truncated).to eq([])
    expect(distribution.unverified).to eq([])
  end

  it "does not mark an error row's synthesized results as truncated" do
    rows = [{ "error" => "boom", "results" => [{ "status" => "error" }] }]
    distribution = account(rows, [[1, 2, 3], [1], [1]])
    expect(distribution.truncated).to eq([])
  end

  it "does not mark a row without results as truncated" do
    distribution = account([{ "error" => "boom" }], [[1, 2, 3], [1], [1]])
    expect(distribution.truncated).to eq([])
  end

  it "marks truncation only when the results are strictly fewer than the candidates" do
    full = { "results" => [{ "status" => "killed" }, { "status" => "killed" }] }
    short = { "results" => [{ "status" => "killed" }] }
    over = { "results" => [{ "status" => "killed" }] * 3 }
    distribution = account([full, short, over], [[1, 2], [1, 2], [1, 2]])
    expect(distribution.truncated).to eq([[:b, 1]])
    expect(distribution.unreached).to eq([])
  end

  it "accounts a serial subject only for strictly omitted candidates" do
    scheduler = ->(_subject, list) { list.first(2) }
    distribution = described_class.new(jobs: 1, scheduler:, diagnostics:, cache: nil)
    distribution.run(%i[a], [[1, 2]])
    expect(distribution.truncated).to eq([])
    short = described_class.new(jobs: 1, scheduler: ->(_s, list) { list.first(1) }, diagnostics:, cache: nil)
    short.run(%i[a], [[1, 2]])
    expect(short.truncated).to eq([[:a, 1]])
  end
end
