# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::Scheduler, "independent fine execution" do
  around { |example| Dir.mktmpdir { |root| @root = File.realpath(root) and example.run } }
  let(:target) { subjects_in("class CoarseTarget\n  def value(a)\n    a + 1\n  end\nend\n").first }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { target.file => { 3 => ["t1"] } }, tests: ["t1"])
  end
  let(:candidates) do
    all = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics).for(target)
    [all.find { |mutation, _| mutation.operator == "body_nil" }, all.find { |mutation, _| !mutation.coarse }]
  end
  let(:calls) { [] }

  def cache
    Saboteur::Engine::ResultCache.new(path: File.join(@root, "results.json"), root: @root, inputs: "same")
  end

  def result(pair, status)
    mutation, text = pair
    Saboteur::MutantResult.new(subject: target, mutation: mutation, mutated_source: text, status: status,
                               covered_by: ["t1"], killed_by: status == :killed ? ["t1"] : [], runtime: 0.1)
  end

  def run(coarse:, fine:, store: nil)
    runner = double("runner")
    allow(runner).to receive(:run) do |mutation: nil, **|
      calls << mutation
      status = if mutation
                 mutation.coarse ? coarse : fine
               else
                 :survived
               end
      Saboteur::Execution::Runner::Outcome.new(status: status, runtime: 0.1,
                                               failed_ids: status == :killed ? ["t1"] : [])
    end
    scheduler = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                    reevaluator: Saboteur::Execution::Reevaluator.new,
                                    diagnostics: diagnostics, cache: store)
    allow(scheduler).to receive(:load_problem).and_return(nil)
    scheduler.call(target, candidates).tap { store&.save }
  end

  %i[survived killed error timeout].each do |coarse|
    it "executes fine mutants after a fresh #{coarse} coarse verdict" do
      results = run(coarse: coarse, fine: :killed)
      expect(results.map(&:status)).to eq([coarse, :killed])
      expect(calls.compact.map(&:coarse)).to eq([true, false])
    end
  end

  [%i[survived killed], %i[killed survived], %i[timeout survived]].each do |coarse, fine|
    it "keeps #{coarse} coarse and #{fine} fine results with a partial cache and then all_reused" do
      store = cache
      store.record(result(candidates.first, coarse))
      # Old gate omissions are skips, which ResultCache must never persist.
      store.record(result(candidates.last, :skipped))
      store.save
      first = run(coarse: coarse, fine: fine, store: cache)
      expect(first.map(&:status)).to eq([coarse, fine])
      expect(first.map(&:reused?)).to eq([true, false])
      expect(calls.compact.map(&:coarse)).to eq([false])
      calls.clear
      expect_any_instance_of(described_class).not_to receive(:checked)
      second = run(coarse: coarse, fine: fine, store: cache)
      expect(second.map(&:status)).to eq([coarse, fine])
      expect(second).to all(be_reused)
      expect(calls).to be_empty
    end
  end
end
