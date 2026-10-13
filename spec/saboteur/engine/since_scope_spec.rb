# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# A --since run without --test has no scoped spec list, so the two
# baseline passes and the coverage-map pass run the whole suite. The run
# must say so - and how to scope it - before those hours pass.
RSpec.describe Saboteur::Engine, "--since without --test" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return({})
  end

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
    @engine = described_class.new(Saboteur::Config.new({ "jobs" => 2 }.merge(overrides), root: @root), err: err)
    @engine.call
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
      "Pass --test to scope it, or --guess-tests to scope it to the specs named after the changed files."
    )
    expect(err.string.index("running the loaded suite unscoped"))
      .to be < err.string.index("checking the unchanged suite")
    expect(report.warnings).to include(
      "running the loaded suite unscoped: two baseline passes; coverage may add a pass (3 spec files). " \
      "Pass --test to scope it, or --guess-tests to scope it to the specs named after the changed files."
    )
  end

  describe "--guess-tests" do
    def guess(specs:, unmatched:, changed:)
      result = Saboteur::Engine::TestGuess::Result.new(specs:, unmatched:, changed:)
      allow(Saboteur::Engine::TestGuess).to receive(:new).and_return(instance_double(Saboteur::Engine::TestGuess,
                                                                                     call: result))
    end

    def tests_the_run_used
      yield
      used = nil
      expect(Saboteur::Engine::CoverageStore).to have_received(:new) do |**arguments|
        used = arguments[:config]["tests"]
        @scoped_root = arguments[:config].root
      end
      used
    end

    it "scopes the run to the guessed specs and says which" do
      guess(specs: %w[spec/a_spec.rb spec/b_spec.rb], unmatched: [], changed: 2)
      used = tests_the_run_used { @report = run_engine("since" => "origin/main", "guess_tests" => true) }
      expect(used).to eq(%w[spec/a_spec.rb spec/b_spec.rb])
      expect(Saboteur::Engine::TestGuess).to have_received(:new).with(an_instance_of(Saboteur::Config))
      expect(@scoped_root).to eq(@root)
      expect(err.string).to include("--guess-tests: running only spec/a_spec.rb, spec/b_spec.rb. A spec that reaches")
      expect(err.string).not_to include("running the loaded suite unscoped")
      expect(@report.warnings).to include(a_string_starting_with("--guess-tests: running only"))
      expect(err.string).to include("is reported as NoCoverage")
      expect(@engine.guessed_tests).to eq(%w[spec/a_spec.rb spec/b_spec.rb])
    end

    it "runs the whole suite and names the files without a spec" do
      guess(specs: ["spec/a_spec.rb"], unmatched: %w[lib/b.rb lib/c.rb], changed: 3)
      used = tests_the_run_used { run_engine("since" => "origin/main", "guess_tests" => true) }
      expect(used).to eq([])
      expect(@engine.guessed_tests).to be_nil
      expect(err.string).to include("--guess-tests: no spec found for lib/b.rb, lib/c.rb, so the whole suite runs " \
                                    "(name specs after their source files or pass --test)")
      expect(err.string).to include("running the loaded suite unscoped")
    end

    it "runs the whole suite when nothing changed" do
      guess(specs: [], unmatched: [], changed: 0)
      run_engine("since" => "origin/main", "guess_tests" => true)
      expect(err.string).to include("--guess-tests: no changed source file to guess specs for, so the whole suite runs")
    end

    it "does not guess without the flag" do
      allow(Saboteur::Engine::TestGuess).to receive(:new)
      run_engine("since" => "origin/main")
      expect(Saboteur::Engine::TestGuess).not_to have_received(:new)
    end
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
