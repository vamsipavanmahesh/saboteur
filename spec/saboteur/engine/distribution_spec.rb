# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Distribution do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }

  it "invokes after_subject with each subject's results in serial" do
    scheduler = ->(subject, list) { [subject, list] }
    seen = []
    distribution = described_class.new(jobs: 1, scheduler:, diagnostics:, cache: nil,
                                       after_subject: ->(subject, results) { seen << [subject, results] })
    distribution.run(%i[a b], [["la"], ["lb"]])
    expect(seen).to eq([[:a, [:a, ["la"]]], [:b, [:b, ["lb"]]]])
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
      .to raise_error(Saboteur::CanaryTripped, "canary: trip")
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

  def fixture_subject
    subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
  end

  def fixture_mutation(subject)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: subject.file_source.index("1"),
                                              end_byte: subject.file_source.index("1") + 1, replacement: "2")
    Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
  end

  it "warns and returns error results when a worker row carries an error" do
    subject = fixture_subject
    mutation = fixture_mutation(subject)
    scheduler = ->(_subject, _list) { raise "worker exploded" }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    results = distribution.run([subject], [[[mutation, "text"]]])
    expect(results.map(&:status)).to eq([:error])
    expect(results.first.reason).to include("worker exploded")
    expect(diagnostics.warnings.join).to include("K#m: RuntimeError: worker exploded")
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
