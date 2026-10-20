# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Distribution, "halt pins" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subjects) { Array.new(3) { |index| subjects_in("class K#{index}\n  def m = 1\nend\n").first } }
  let(:lists) { subjects.map { |subject| [[comparison_mutation, "text for #{subject.id}"]] } }
  let(:scheduler) do
    lambda do |subject, list|
      mutation, text = list.first
      [Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :killed, mutated_source: text)]
    end
  end

  def distribution(jobs:, **options)
    described_class.new(jobs: jobs, scheduler: scheduler, diagnostics: diagnostics, cache: nil, **options)
  end

  it "leaves the subjects after the one that triggered stop_after unreached, not that subject" do
    calls = 0
    run = distribution(jobs: 1, stop_after: ->(_results) { (calls += 1) == 2 })
    expect(run.run(subjects, lists).map { |result| result.subject.id }).to eq(%w[K0#m K1#m])
    expect(run.unreached).to eq([subjects.last])
  end

  it "halts the pool without draining when the budget is spent after an arrival" do
    expect_any_instance_of(Saboteur::Execution::WorkerPool)
      .to receive(:halt!).with(drain: false).at_least(:once).and_call_original
    calls = 0
    run = distribution(jobs: 2, halt_check: -> { (calls += 1) > 1 })
    run.run(subjects, lists)
    expect(run.unreached).to eq([subjects.last])
  end
end
