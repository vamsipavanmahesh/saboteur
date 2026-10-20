# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Distribution, "pins" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subjects) { Array.new(3) { |index| subjects_in("class K#{index}\n  def m = 1\nend\n").first } }
  let(:lists) { subjects.map { |subject| [[comparison_mutation, "text for #{subject.id}"]] } }
  let(:scheduler) do
    lambda do |subject, list|
      mutation, text = list.first
      [Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :killed, mutated_source: text,
                                  executed: ["t-#{subject.id}"])]
    end
  end

  def distribution(jobs:, **options)
    described_class.new(jobs: jobs, scheduler: scheduler, diagnostics: diagnostics, cache: nil, **options)
  end

  def counter(after:)
    calls = 0
    -> { (calls += 1) > after }
  end

  describe "run in serial" do
    it "starts no subject when the budget is already spent, and calls them all unreached" do
      run = distribution(jobs: 1, halt_check: -> { true })
      expect(run.run(subjects, lists)).to eq([])
      expect(run.unreached).to eq(subjects)
    end

    it "runs every subject when the budget check says no" do
      run = distribution(jobs: 1, halt_check: -> { false })
      expect(run.run(subjects, lists).size).to eq(3)
      expect(run.unreached).to eq([])
    end

    it "stops before the next subject once the budget is spent" do
      run = distribution(jobs: 1, halt_check: counter(after: 1))
      expect(run.run(subjects, lists).map { |result| result.subject.id }).to eq(["K0#m"])
      expect(run.unreached).to eq(subjects.drop(1))
    end

    it "asks stop_after with the subject's results, and stops when it says so" do
      seen = []
      run = distribution(jobs: 1, stop_after: lambda { |results|
        seen << results.map { |result| result.subject.id }
        true
      })
      expect(run.run(subjects, lists).size).to eq(1)
      expect(seen).to eq([["K0#m"]])
      expect(run.unreached).to eq(subjects.drop(1))
    end

    it "keeps going when stop_after says no" do
      run = distribution(jobs: 1, stop_after: ->(_results) { false })
      expect(run.run(subjects, lists).size).to eq(3)
      expect(run.unreached).to eq([])
    end
  end

  describe "run in parallel" do
    it "starts nothing when the budget is already spent" do
      run = distribution(jobs: 2, halt_check: -> { true })
      expect(run.run(subjects, lists)).to eq([])
      expect(run.unreached).to eq(subjects)
    end

    it "runs every subject when the budget check says no, and keeps what each result executed" do
      run = distribution(jobs: 2, halt_check: -> { false })
      results = run.run(subjects, lists)
      expect(results.map { |result| result.subject.id }).to eq(%w[K0#m K1#m K2#m])
      expect(results.map(&:executed)).to eq([["t-K0#m"], ["t-K1#m"], ["t-K2#m"]])
      expect(run.unreached).to eq([])
    end

    it "hands out no more work once an arrival finds the budget spent" do
      run = distribution(jobs: 2, halt_check: counter(after: 1))
      results = run.run(subjects, lists)
      expect(results.size).to eq(2)
      expect(run.unreached).to eq([subjects.last])
    end
  end
end
