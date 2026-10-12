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

  it "uses the worker pool when jobs is above one" do
    scheduler = ->(subject, _list) { [subject] }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil)
    allow(Saboteur::Execution::WorkerPool).to receive(:new).and_raise(Saboteur::Error, "pool started")
    expect { distribution.run(%i[a], [[]]) }.to raise_error(Saboteur::Error, "pool started")
  end
end
