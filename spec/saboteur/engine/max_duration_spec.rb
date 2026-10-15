# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine, "--max-duration budget (#245)" do
  def engine_with(config_values, err)
    described_class.new(Saboteur::Config.new(config_values, root: Dir.mktmpdir), err: err)
  end

  it "starts the clock at the first check and trips only once the budget passes, announcing once" do
    err = StringIO.new
    engine = engine_with({ "max_duration" => 60 }, err)
    times = [100.0, 100.0, 161.0, 200.0].each
    allow(Process).to receive(:clock_gettime) { times.next }

    expect(engine.send(:budget_exceeded?)).to eq(false)
    expect(engine.send(:budget_exceeded?)).to eq(true)
    expect(engine.send(:budget_exceeded?)).to eq(true)
    expect(err.string.scan("--max-duration reached").size).to eq(1)
  end

  it "never trips without a configured budget" do
    engine = engine_with({}, StringIO.new)
    expect(engine.send(:budget_exceeded?)).to eq(false)
  end
end

RSpec.describe Saboteur::Engine::Distribution, "max-duration halt (#245)" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }

  it "halts the pool when the check fires, leaves nil holes unreached, and still rebuilds finished rows" do
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: subject.file_source.index("1"),
                                              end_byte: subject.file_source.index("1") + 1, replacement: "2")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "x")]
    scheduler = ->(_subject, _list) { row }
    spent = false
    halt_check = lambda {
      seen = spent
      spent = true
      seen
    }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil, halt_check: halt_check)
    subjects = Array.new(6) { subject }
    lists = Array.new(6) { [[mutation, "text"]] }
    results = distribution.run(subjects, lists)
    expect(results.map(&:status)).to all(eq(:killed))
    expect(distribution.unreached).not_to be_empty
    expect(distribution.unreached.size).to be < 6
    expect(results.size + distribution.unreached.size).to eq(6)
  end
end
