# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# An order-dependent file (#557): an early example sets state up and a later
# one asserts on it. Running the covering example alone fails even with the
# method unchanged. The scheduler retries such a mutant with the file's
# examples in defined order, up to the last covering example, before it
# gives up and bins the mutant as error.
RSpec.describe Saboteur::Engine::Scheduler, "order-dependent spec files (#557)" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subject_under_test) { subjects_in("class OrderTarget\n  def m(a)\n    a + 1\n  end\nend\n").first }
  let(:setup_example) { "./spec/order_spec.rb[1:1]" }
  let(:asserting_example) { "./spec/order_spec.rb[1:2]" }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(
      lines: { subject_under_test.file => { 3 => [asserting_example] } },
      tests: [asserting_example, "./spec/other_spec.rb[1:1]", setup_example],
      durations: { asserting_example => 0.1, setup_example => 0.1, "./spec/other_spec.rb[1:1]" => 0.1 }
    )
  end
  let(:candidates) { Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics) }
  let(:runner) { instance_double(Saboteur::Execution::Runner) }
  let(:runs) { [] }

  def outcome(status, failed_ids: [], message: nil)
    Saboteur::Execution::Runner::Outcome.new(status: status, runtime: 0.1, failed_ids: failed_ids, message: message)
  end

  # The asserting example fails unless the setup example ran before it.
  def fake_runner(mutant_kills_in_prefix: false)
    allow(runner).to receive(:run) do |test_ids:, mutation: nil, **|
      runs << [mutation ? :mutant : :unchanged, test_ids]
      has_setup = test_ids.include?(setup_example) && test_ids.index(setup_example) < test_ids.index(asserting_example)
      if !has_setup then outcome(:killed, failed_ids: [asserting_example], message: "Structure missing")
      elsif mutation && mutant_kills_in_prefix then outcome(:killed, failed_ids: [asserting_example])
      else outcome(:survived)
      end
    end
  end

  def results
    sched = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics)
    allow(sched).to receive(:load_problem).and_return(nil)
    sched.call(subject_under_test, candidates.for(subject_under_test))
  end

  it "does not bin the mutant as error when the setup example runs first in defined order" do
    fake_runner
    expect(results.map(&:status).uniq).to eq([:survived])
  end

  it "retries with the file's examples from the start through the last covering example" do
    fake_runner
    results
    expect(runs).to include([:unchanged, [setup_example, asserting_example]],
                            [:mutant, [setup_example, asserting_example]])
  end

  it "keeps a kill that still fails in the defined-order prefix and passes unchanged there" do
    fake_runner(mutant_kills_in_prefix: true)
    expect(results.map(&:status).uniq).to eq([:killed])
  end

  it "leaves the mutant as error when the covering example also fails unchanged in the prefix" do
    allow(runner).to receive(:run) do |mutation: nil, **|
      mutation ? outcome(:killed, failed_ids: [asserting_example]) : outcome(:killed, message: "still broken")
    end
    expect(results.map(&:status).uniq).to eq([:error])
  end

  it "does not retry an example that already runs first in its file" do
    first = "./spec/order_spec.rb[1:1]"
    allow(map).to receive(:tests_for).and_return([first])
    allow(runner).to receive(:run) do |test_ids:, mutation: nil, **|
      runs << [mutation ? :mutant : :unchanged, test_ids]
      mutation ? outcome(:killed, failed_ids: [first]) : outcome(:killed, message: "broken")
    end
    results
    expect(runs.map(&:last).uniq).to eq([[first]])
  end
end
