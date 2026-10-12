# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# A --since run without --test has no scoped spec list, so the two
# baseline passes and the coverage-map pass run the whole suite. The run
# must say so - and how to scope it - before those hours pass.
RSpec.describe Saboteur::Engine, "--since without --test" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:subject_under_test) do
    subjects_in("class SinceTarget\n  def m\n    1\n  end\nend\n", name: "since_target.rb").first
  end
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => ["t1"] } }, tests: ["t1"])
  end
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: %w[a_spec.rb b_spec.rb c_spec.rb]) }
  let(:err) { StringIO.new }

  def run_engine(overrides)
    stub_boot_phase
    stub_test_phases
    described_class.new(Saboteur::Config.new({ "jobs" => 2 }.merge(overrides), root: @root), err: err).call
  end

  def stub_boot_phase
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject_under_test], changed_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  def stub_test_phases
    # The real guard's first line; lets the ordering assertion see when the
    # baseline passes begin.
    baseline = instance_double(Saboteur::Engine::BaselineGuard)
    allow(baseline).to receive(:call) { err.puts("saboteur: checking the unchanged suite twice (seed 1)") }
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
    store = instance_double(Saboteur::Engine::CoverageStore)
    allow(store).to receive(:fetch).and_return(map)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    distribution = instance_double(Saboteur::Engine::Distribution, run: [])
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
  end

  it "warns about the unscoped suite before the baseline passes start" do
    report = run_engine("since" => "origin/main")
    expect(err.string).to include(
      "running the loaded suite unscoped: two baseline passes; coverage may add a pass (3 spec files). " \
      "Pass --test to scope it."
    )
    expect(err.string.index("running the loaded suite unscoped"))
      .to be < err.string.index("checking the unchanged suite")
    expect(report.warnings).to include(
      "running the loaded suite unscoped: two baseline passes; coverage may add a pass (3 spec files). " \
      "Pass --test to scope it."
    )
  end

  it "says nothing when --test scopes the specs" do
    run_engine("since" => "origin/main", "tests" => ["a_spec.rb"])
    expect(err.string).not_to include("running the loaded suite unscoped")
  end

  it "says nothing without --since" do
    run_engine({})
    expect(err.string).not_to include("running the loaded suite unscoped")
  end
end
