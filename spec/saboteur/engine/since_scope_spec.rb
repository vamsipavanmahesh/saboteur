# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# Without --test the run infers its specs from the mutated files by naming
# convention (0.7.0). --all keeps the whole configured suite, and then the
# two baseline passes and the coverage-map pass run everything. The run
# must say so - and how to scope it - before those hours pass. A mutated
# file with no spec named after it stops the run before boot with a usage
# error naming both ways out.
RSpec.describe Saboteur::Engine, "test selection" do
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
    distribution = instance_double(Saboteur::Engine::Distribution, run: [], unreached: [])
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
  end

  def guess(specs:, unmatched:, changed:, subjectless: [])
    hints = unmatched.to_h { |file| [file, "spec/#{File.basename(file, '.rb')}_spec.rb"] }
    result = Saboteur::Engine::TestGuess::Result.new(specs:, unmatched:, subjectless:, changed:, hints:)
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

  it "warns about the unscoped suite before the baseline passes start" do
    report = run_engine("since" => "origin/main", "all" => true)
    warning = "running the loaded suite unscoped: two baseline passes; coverage may add a pass (3 spec files). " \
              "Pass --test to run only the specs you name: faster, but a mutant of a changed method is then killed " \
              "only by those specs, so specs elsewhere that call this code are not run. " \
              "The default inferred selection runs the specs named after the mutated files, " \
              "a guess that can miss specs elsewhere."
    expect(err.string).to include(warning)
    expect(err.string.index("running the loaded suite unscoped"))
      .to be < err.string.index("checking the unchanged suite")
    expect(report.warnings).to include(warning)
  end

  describe "inferred specs (the default)" do
    it "scopes the run to the inferred specs and says which" do
      guess(specs: %w[spec/a_spec.rb spec/b_spec.rb], unmatched: [], changed: 2)
      used = tests_the_run_used { @report = run_engine("since" => "origin/main") }
      expect(used).to eq(%w[spec/a_spec.rb spec/b_spec.rb])
      expect(Saboteur::Engine::TestGuess).to have_received(:new).with(an_instance_of(Saboteur::Config))
      expect(@scoped_root).to eq(@root)
      expect(err.string).to include("inferred specs: running only spec/a_spec.rb, spec/b_spec.rb. A spec that reaches")
      expect(err.string).not_to include("running the loaded suite unscoped")
      expect(@report.warnings).to include(a_string_starting_with("inferred specs: running only"))
      expect(err.string).to include("is reported as NoCoverage")
      expect(@engine.guessed_tests).to eq(%w[spec/a_spec.rb spec/b_spec.rb])
      expect(err.string).not_to include("no spec is required")
    end

    it "stops before boot when a changed file has no spec named after it" do
      guess(specs: ["spec/a_spec.rb"], unmatched: %w[lib/b.rb lib/c.rb], changed: 3)
      message = "no spec found for lib/b.rb, lib/c.rb, so nothing ran. Either name the specs to run:\n  " \
                "saboteur run --since origin/main --test spec/b_spec.rb --test spec/c_spec.rb\n" \
                "or run the whole suite:\n  saboteur run --since origin/main --all"
      expect { run_engine("since" => "origin/main") }.to raise_error(Saboteur::ConfigError, message)
      expect(Saboteur::Engine::CoverageStore).not_to have_received(:new)
    end

    it "stops before boot when no changed file has a spec" do
      guess(specs: [], unmatched: ["lib/b.rb"], changed: 1)
      expect { run_engine("since" => "origin/main") }
        .to raise_error(Saboteur::ConfigError, %r{no spec found for lib/b\.rb, so nothing ran})
      expect(Saboteur::Engine::CoverageStore).not_to have_received(:new)
    end

    it "says there is nothing to mutate when no changed file has a mutation subject" do
      guess(specs: [], unmatched: [], changed: 1, subjectless: ["lib/errors.rb"])
      used = tests_the_run_used { run_engine("since" => "origin/main") }
      expect(used).to eq([])
      expect(@engine.guessed_tests).to be_nil
      expect(err.string).to include("inferred specs: no changed file has a mutation subject on its changed lines, " \
                                    "so there is nothing to mutate")
      expect(err.string).to include("no spec is required for lib/errors.rb: they have no changed mutation subjects")
      expect(err.string).not_to include("the whole suite runs")
    end

    it "notes skipped subjectless files while scoping to the inferred specs" do
      guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 2, subjectless: ["lib/errors.rb"])
      used = tests_the_run_used { run_engine("since" => "origin/main") }
      expect(used).to eq(["spec/a_spec.rb"])
      expect(err.string).to include("inferred specs: running only spec/a_spec.rb")
      expect(err.string).to include("no spec is required for lib/errors.rb")
    end

    it "runs the whole suite when nothing changed" do
      guess(specs: [], unmatched: [], changed: 0)
      run_engine("since" => "origin/main")
      expect(err.string).to include("inferred specs: no changed source file to infer a spec for, " \
                                    "so the whole suite runs")
    end

    it "names every subjectless file in the note" do
      guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 3, subjectless: ["lib/b.rb", "lib/c.rb"])
      run_engine("since" => "origin/main")
      expect(err.string).to include("no spec is required for lib/b.rb, lib/c.rb:")
    end

    it "infers specs from the configured sources without --since" do
      guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 1)
      used = tests_the_run_used { run_engine({}) }
      expect(used).to eq(["spec/a_spec.rb"])
      expect(err.string).to include("inferred specs: running only spec/a_spec.rb")
      expect(err.string).not_to include("running the loaded suite unscoped")
    end

    it "names the source in the stop-before-boot retry commands without --since" do
      guess(specs: [], unmatched: ["lib/b.rb"], changed: 1)
      expect { run_engine({}) }
        .to raise_error(Saboteur::ConfigError, %r{saboteur run lib/b\.rb --test spec/b_spec\.rb\n})
      expect { run_engine({}) }
        .to raise_error(Saboteur::ConfigError, %r{saboteur run lib/b\.rb --all})
    end
  end

  describe "--all" do
    it "keeps the whole suite and skips inference" do
      allow(Saboteur::Engine::TestGuess).to receive(:new)
      used = tests_the_run_used { @report = run_engine("since" => "origin/main", "all" => true) }
      expect(used).to eq([])
      expect(Saboteur::Engine::TestGuess).not_to have_received(:new)
      expect(@engine.guessed_tests).to be_nil
      expect(err.string).to include("running the loaded suite unscoped")
    end

    it "keeps the whole suite through c.test_selection = :all" do
      allow(Saboteur::Engine::TestGuess).to receive(:new)
      used = tests_the_run_used { run_engine("since" => "origin/main", "test_selection" => "all") }
      expect(used).to eq([])
      expect(Saboteur::Engine::TestGuess).not_to have_received(:new)
      expect(err.string).to include("running the loaded suite unscoped")
    end
  end

  it "does not infer when --test scopes the specs" do
    allow(Saboteur::Engine::TestGuess).to receive(:new)
    run_engine("since" => "origin/main", "tests" => ["a_spec.rb"])
    expect(Saboteur::Engine::TestGuess).not_to have_received(:new)
    expect(err.string).not_to include("running the loaded suite unscoped")
  end

  it "says nothing about the suite when inference narrows without --since" do
    guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 1)
    run_engine({})
    expect(err.string).not_to include("running the loaded suite unscoped")
  end
end
