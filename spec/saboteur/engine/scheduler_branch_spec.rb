# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Scheduler, "branch filtering" do
  let(:target) { subjects_in("class BranchScheduler\n  def m(x)\n    x ? 10 : 20\n  end\nend\n").first }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:map) do
    arms = { target.file => { [3, 8, 3, 10] => ["yes"], [3, 13, 3, 15] => [] } }
    Saboteur::Selection::CoverageMap.new(lines: { target.file => { 3 => %w[yes no] } },
                                         tests: %w[yes no], branches: arms)
  end
  let(:scheduler) do
    described_class.new(config: Saboteur::Config.new({}), runner: double("runner"), map: map,
                        reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics)
  end
  let(:plan) { described_class::Plan.new(subject: target, tests: %w[yes no], killers: {}) }

  def mutation(text, coarse: false)
    offset = target.file_source.index(text)
    edit = Saboteur::MutationSource::Edit.new(file: target.file, start_byte: offset,
                                              end_byte: offset + text.bytesize, replacement: "0")
    Saboteur::MutationSource::Mutation.new(subject_id: target.id, operator: "test", edits: [edit], coarse: coarse)
  end

  it "filters covering-line tests to the tests that took the arm" do
    expect(scheduler.send(:tests_for, plan, mutation("10"))).to eq(["yes"])
    expect(scheduler.send(:tests_for, plan, mutation("20"))).to eq([])
    expect(scheduler.send(:tests_for, plan, mutation("10", coarse: true))).to eq(%w[yes no])
  end

  it "reports a branch-specific skip without running an untaken arm" do
    untaken = mutation("20")
    result = scheduler.send(:execute, plan, untaken, target.source)
    expect(result.status).to eq(:skipped)
    expect(result.reason).to eq("no coverage (branch not taken)")
    expect(result.covered_by).to eq([])
    expect(result.mutation).to be(untaken)
    expect(result.mutated_source).to eq(target.source)
  end

  it "gives an uncovered edit with no arm evidence the plain no-coverage reason" do
    map.lines[target.file].clear
    result = scheduler.send(:uncoverable, plan, mutation("x ?"), target.source)
    expect(result.status).to eq(:skipped)
    expect(result.reason).to eq("no coverage")
  end

  it "keeps the plain no-coverage reason when the arm was taken but no line evidence exists" do
    map.lines[target.file].clear
    result = scheduler.send(:uncoverable, plan, mutation("10"), target.source)
    expect(result.reason).to eq("no coverage")
  end
  it "keeps load-only evidence ahead of an untaken example branch" do
    map.load_lines[target.file] = [3]
    map.lines[target.file].clear
    result = scheduler.send(:uncoverable, plan, mutation("20"), target.source)
    expect(result.status).to eq(:ran_at_load)
    expect(result.reason).to eq(Saboteur::Selection::CoverageMap::RAN_AT_LOAD)
  end
end
