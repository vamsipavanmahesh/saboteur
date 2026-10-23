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
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
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
  let(:integration) do
    instance_double(Saboteur::Integration::RSpec, test_files: %w[a_spec.rb b_spec.rb c_spec.rb],
                                                  all_tests: [double(id: "t1"), double(id: "t2"), double(id: "t3")])
  end
  let(:err) { StringIO.new }

  def run_engine(overrides, verbose = nil)
    stub_boot_phase
    stub_test_phases
    @engine = described_class.new(Saboteur::Config.new({ "jobs" => 2 }.merge(overrides), root: @root),
                                  err: err, verbose: verbose || false)
    @engine.call
  end

  def stub_boot_phase
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject_under_test], behavior_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  def stub_test_phases
    # The real guard's first line; lets the ordering assertion see when the
    # baseline passes begin.
    baseline = instance_double(Saboteur::Engine::BaselineGuard, completed_passes: 2)
    allow(baseline).to receive(:call) { err.puts("saboteur: checking the unchanged suite twice (seed 1)") }
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false)
    allow(store).to receive(:fetch).and_return(map)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    distribution = instance_double(Saboteur::Engine::Distribution, memory_report: nil, run: [], unreached: [],
                                                                   truncated: [],
                                                                   unverified: [])
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
  end

  def guess(specs:, unmatched:, changed:, subjectless: [], changed_specs: [], skipped_specs: {}, out_of_scope: [],
            excluded: [], no_suite: nil, referenced: {})
    hints = unmatched.to_h { |file| [file, "spec/#{File.basename(file, '.rb')}_spec.rb"] }
    result = Saboteur::Engine::TestGuess::Result.new(specs:, unmatched:, subjectless:, changed:, hints:,
                                                     changed_specs:, skipped_specs:, out_of_scope:, excluded:,
                                                     no_suite:, referenced:)
    allow(Saboteur::Engine::TestGuess).to receive(:new).and_return(instance_double(Saboteur::Engine::TestGuess,
                                                                                   call: result, call_for: result))
  end

  def tests_the_run_used
    yield
    used = nil
    expect(Saboteur::Engine::CoverageStore).to have_received(:new) do |**arguments|
      used = arguments[:config]["tests"]
      @scoped_root = arguments[:config].root
      @scoped_config = arguments[:config]
    end
    used
  end

  it "carries the distribution's memory report into the run report (#202)" do
    stub_boot_phase
    stub_test_phases
    memory = { workers: [{ worker: 0, peakMb: 12.1 }], supervisorPeakMb: 30.5 }
    distribution = instance_double(Saboteur::Engine::Distribution, memory_report: memory, run: [], unreached: [],
                                                                   truncated: [], unverified: [])
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    guess(specs: %w[spec/a_spec.rb], unmatched: [], changed: 1)
    @engine = described_class.new(Saboteur::Config.new({ "jobs" => 2, "since" => "origin/main" }, root: @root),
                                  err: err)
    @report = @engine.call
    expect(@report.memory).to eq(memory)
  end

  it "warns about the unscoped suite before the baseline passes start" do
    report = run_engine("since" => "origin/main", "all" => true)
    warning = "running the loaded suite unscoped: 3 examples in 3 spec files; " \
              "3 full passes (2 baseline checks + 1 coverage map build)."
    expect(err.string).to include(warning)
    expect(err.string.index("running the loaded suite unscoped"))
      .to be < err.string.index("checking the unchanged suite")
    expect(report.warnings).to include(warning)
  end

  it "counts only the passes the run will really make when the cached coverage map is reusable" do
    stub_boot_phase
    stub_test_phases
    allow(Saboteur::Engine::CoverageStore).to receive(:new)
      .and_return(instance_double(Saboteur::Engine::CoverageStore, reusable?: true, fetch: map))
    described_class.new(Saboteur::Config.new({ "jobs" => 2, "since" => "origin/main", "all" => true }, root: @root),
                        err: err).call
    expect(err.string).to include("2 full passes (2 baseline checks; the cached coverage map is reused)")
    expect(err.string).not_to include("coverage map build")
  end

  it "suggests --test from the example-count threshold up" do
    allow(integration).to receive(:all_tests).and_return(Array.new(1_000) { |i| double(id: "t#{i}") })
    run_engine("since" => "origin/main", "all" => true)
    expect(err.string).to include("1000 examples in 3 spec files", "Pass --test to run only the specs you name")
  end

  it "skips the --test suggestion just under the threshold" do
    allow(integration).to receive(:all_tests).and_return(Array.new(999) { |i| double(id: "t#{i}") })
    run_engine("since" => "origin/main", "all" => true)
    expect(err.string).to include("running the loaded suite unscoped")
    expect(err.string).not_to include("Pass --test to run only the specs you name")
  end

  it "suggests --test past the example-count threshold" do
    allow(integration).to receive(:all_tests).and_return(Array.new(1_001) { |i| double(id: "t#{i}") })
    run_engine("since" => "origin/main", "all" => true)
    expect(err.string).to include("1001 examples in 3 spec files", "Pass --test to run only the specs you name")
  end

  it "does not nag a single-mutant replay about the whole suite's cost (#260)" do
    stub_boot_phase
    stub_test_phases
    engine = described_class.new(Saboteur::Config.new({ "jobs" => 2, "all" => true }, root: @root),
                                 err: err, digest: "0" * 16)
    expect { engine.call }.to raise_error(Saboteur::Error, /not found/)
    expect(err.string).not_to include("running the loaded suite unscoped")
  end

  it "does not nag a replay that resolves and runs its mutant (#260)" do
    stub_boot_phase
    stub_test_phases
    config = Saboteur::Config.new({ "jobs" => 2, "all" => true }, root: @root)
    probe = described_class.new(config, err: err, digest: "0" * 16)
    sources = Saboteur::Engine::Candidates.build_sources(config)
    candidates = Saboteur::Engine::Candidates.new(sources, probe.instance_variable_get(:@diagnostics),
                                                  hazard_guard: probe.send(:hazard_guard))
    mutation, = candidates.for(subject_under_test).first
    digest = mutation.digest(subject_start: subject_under_test.start_byte,
                             original_source: subject_under_test.file_source)
    described_class.new(config, err: err, digest: digest).call
    expect(err.string).not_to include("running the loaded suite unscoped")
  end

  it "skips the --test suggestion below the example-count threshold" do
    run_engine("since" => "origin/main", "all" => true)
    expect(err.string).to include("running the loaded suite unscoped")
    expect(err.string).not_to include("Pass --test to run only the specs you name")
  end

  it "says something while the application loads, before any pass starts" do
    run_engine({ "since" => "origin/main", "all" => true }, true)
    expect(err.string).to include("loading the application")
    expect(err.string.index("loading the application"))
      .to be < err.string.index("checking the unchanged suite")
  end

  describe "inferred specs (the default)" do
    it "carries the files chosen by reference from the guess into the report" do
      chosen = { "lib/a.rb" => %w[spec/features/a_spec.rb] }
      guess(specs: %w[spec/features/a_spec.rb], unmatched: [], changed: 1, referenced: chosen)
      expect(run_engine("since" => "origin/main").referenced).to eq(chosen)
    end

    it "reports no referenced files when the run chose no specs from a guess" do
      expect(run_engine("since" => "origin/main", "all" => true).referenced).to eq({})
    end

    it "names the specs changed in the diff and the ones it deleted (#307)" do
      guess(specs: %w[spec/a_spec.rb spec/requests/a_spec.rb], unmatched: [], changed: 1,
            changed_specs: %w[spec/requests/a_spec.rb],
            skipped_specs: { "spec/old_spec.rb" => "deleted in the diff" })
      used = tests_the_run_used { run_engine({ "since" => "origin/main" }, true) }
      expect(used).to eq(%w[spec/a_spec.rb spec/requests/a_spec.rb])
      expect(err.string).to include("inferred specs: running only spec/a_spec.rb, spec/requests/a_spec.rb " \
                                    "(changed in the diff: spec/requests/a_spec.rb). A spec the diff did not change " \
                                    "that reaches",
                                    "inferred specs: not running spec files changed in the diff: " \
                                    "spec/old_spec.rb (deleted in the diff)")
    end

    it "says nothing about skipped specs when the diff skips none" do
      guess(specs: %w[spec/a_spec.rb], unmatched: [], changed: 1)
      tests_the_run_used { run_engine("since" => "origin/main") }
      expect(err.string).not_to include("not running spec files")
    end

    it "scopes the run to the inferred specs and says which" do
      guess(specs: %w[spec/a_spec.rb spec/b_spec.rb], unmatched: [], changed: 2)
      used = tests_the_run_used { @report = run_engine({ "since" => "origin/main" }, true) }
      expect(used).to eq(%w[spec/a_spec.rb spec/b_spec.rb])
      expect(Saboteur::Engine::TestGuess).to have_received(:new)
        .with(an_instance_of(Saboteur::Config), diagnostics: @engine.instance_variable_get(:@diagnostics),
                                                custom_map: an_instance_of(Saboteur::CustomMap))
      expect(@scoped_root).to eq(@root)
      expect(err.string).not_to include("intentionally untested")
      expect(err.string).to include("inferred specs: running only spec/a_spec.rb, spec/b_spec.rb. " \
                                    "A spec the diff did not change that reaches")
      expect(err.string).not_to include("running the loaded suite unscoped")
      # Report consumers discard stderr: the caveat must stay in
      # report.warnings (#605 security review).
      expect(@report.warnings).to include(a_string_starting_with("inferred specs: running only"))
      expect(err.string).to include("is reported as NoCoverage")
      # ...while printing exactly once to the terminal, up front (#605).
      expect(err.string.scan("inferred specs: running only").size).to eq(1)
      expect(@engine.guessed_tests).to eq(%w[spec/a_spec.rb spec/b_spec.rb])
      expect(err.string).not_to include("no spec is required")
    end

    # End to end: the caveat must reach the terminal exactly once through
    # the whole chain - diagnostics announce, Report#live_announced, and
    # the terminal's skip of live-announced warnings (#605, Pod 1 KC1/KC2).
    it "prints the blind-spot caveat exactly once across the whole run and report (#605)" do
      guess(specs: %w[spec/a_spec.rb spec/b_spec.rb], unmatched: [], changed: 2)
      @report = run_engine({ "since" => "origin/main" }, true)
      Saboteur::Reporter::Terminal.new(err).call(@report)

      expect(@report.warnings).to include(a_string_starting_with("inferred specs: running only"))
      expect(err.string.scan("inferred specs: running only").size).to eq(1)
    end

    it "keeps explicit-key provenance through the scoped config clone (#296)" do
      guess(specs: %w[spec/a_spec.rb], unmatched: [], changed: 1)
      tests_the_run_used { run_engine("since" => "origin/main", "json_report" => "custom.json") }
      expect(@engine.config.explicit?("json_report")).to be(true)
      expect(@engine.config.explicit?("html_report")).to be(false)
      expect(@engine.config.explicit?("tests")).to be(true)
    end

    # One unmapped changed file must not zero the run: the mapped subset
    # runs and each unmapped file gets a loud warning (#370).
    it "runs the mapped subset with a loud warning per unmapped file" do
      guess(specs: ["spec/a_spec.rb"], unmatched: %w[lib/b.rb lib/c.rb], changed: 3)
      used = tests_the_run_used { run_engine("since" => "origin/main") }
      expect(used).to eq(["spec/a_spec.rb"])
      expect(err.string).to include("inferred specs: no spec found for lib/b.rb (expected spec/b_spec.rb)")
        .and include("inferred specs: no spec found for lib/c.rb (expected spec/c_spec.rb)")
      expect(err.string).to include("lib/b.rb (expected spec/b_spec.rb); its mutants run only " \
                                    "against the inferred specs and a line they miss is reported as NoCoverage")
    end

    # The partial-mapping announce path returns the files it warned about:
    # each hands the list back, a map swap would hand back the announcements
    # (#692; pins the each against a method_swap).
    it "returns the unmatched files it announces in a partial --since mapping" do
      result = Saboteur::Engine::TestGuess::Result.new(specs: ["spec/a_spec.rb"], unmatched: ["lib/b.rb"],
                                                       subjectless: [], changed: 2,
                                                       hints: { "lib/b.rb" => "spec/b_spec.rb" })
      engine = described_class.new(Saboteur::Config.new({ "since" => "origin/main" }, root: @root), err: err)
      expect(engine.send(:stop_or_warn_unmapped, result)).to eq(["lib/b.rb"])
    end

    # The stop's message is built with the run's verbosity: under --verbose
    # the no-suite line carries the per-file expected-spec list (#692).
    it "passes verbose through to the full-run stop's message" do
      guess(specs: [], unmatched: ["lib/b.rb"], changed: 1, no_suite: :plain)
      stub_boot_phase
      stub_test_phases
      @engine = described_class.new(Saboteur::Config.new({ "jobs" => 2 }, root: @root), err: err, verbose: true)
      expect { @engine.call }.to raise_error(Saboteur::ConfigError, %r{Files without a guessed spec: lib/b\.rb})
    end

    it "passes verbose through to the subject-run stop's message" do
      guess(specs: ["spec/a_spec.rb"], unmatched: ["lib/b.rb"], changed: 2, no_suite: :plain)
      allow(Saboteur::Engine::SubjectSelection).to receive(:files_matching).and_return(%w[lib/a.rb lib/b.rb])
      stub_boot_phase
      stub_test_phases
      @engine = described_class.new(Saboteur::Config.new({ "jobs" => 2, "subjects" => ["A#a", "B#b"] }, root: @root),
                                    err: err, verbose: true)
      expect { @engine.call }.to raise_error(Saboteur::ConfigError, %r{Files without a guessed spec: lib/b\.rb})
    end

    # A threshold or mutant-count gate judges the score, and a partial
    # mapping silently narrows what the score covers: keep the hard stop
    # so a gated run cannot green-light an unverifiable change (#370).
    it "stops on a partial mapping when a threshold is configured" do
      guess(specs: ["spec/a_spec.rb"], unmatched: ["lib/b.rb"], changed: 2)
      expect { run_engine("since" => "origin/main", "threshold" => 100) }
        .to raise_error(Saboteur::ConfigError, %r{no spec found for lib/b\.rb})
    end

    it "stops on a partial mapping when a mutant-count gate is configured" do
      guess(specs: ["spec/a_spec.rb"], unmatched: ["lib/b.rb"], changed: 2)
      expect { run_engine("since" => "origin/main", "max_errors" => 0) }
        .to raise_error(Saboteur::ConfigError, %r{no spec found for lib/b\.rb})
    end

    # The partial-mapping mercy is scoped to --since: a named --subject
    # without a conventional spec still stops the run before boot (#370).
    it "still stops a --subject run on an unmapped named subject" do
      guess(specs: ["spec/a_spec.rb"], unmatched: ["lib/b.rb"], changed: 2)
      allow(Saboteur::Engine::SubjectSelection).to receive(:files_matching).and_return(%w[lib/a.rb lib/b.rb])
      expect { run_engine("subjects" => ["A#a", "B#b"]) }
        .to raise_error(Saboteur::ConfigError, %r{no spec found for lib/b\.rb})
    end

    # The partial-mapping mercy is scoped to --since: a full run keeps the
    # hard stop even when other changed files have specs (#370).
    it "stops a full run on a partial mapping even when other files have specs" do
      guess(specs: ["spec/a_spec.rb"], unmatched: ["lib/b.rb"], changed: 2)
      expect { run_engine({}) }.to raise_error(Saboteur::ConfigError, %r{no spec found for lib/b\.rb})
    end

    it "stops before boot when no changed file has a spec" do
      guess(specs: [], unmatched: ["lib/b.rb"], changed: 1)
      expect { run_engine("since" => "origin/main") }
        .to raise_error(Saboteur::ConfigError,
                        %r{no spec found for lib/b\.rb \(expected spec/b_spec\.rb\), so nothing ran})
      expect(Saboteur::Engine::CoverageStore).not_to have_received(:new)
    end

    # Every file in scope intentionally untested: name them and mutate
    # nothing; an empty guess must never read as "run the whole suite"
    # (#369 review).
    # A mixed guess: the excluded files are named AND the matched specs
    # still run - the exclusion note must not depend on an empty run
    # (#369 review dogfood).
    it "names excluded files alongside the specs that still run" do
      guess(specs: ["a_spec.rb"], unmatched: [], changed: 2, excluded: ["lib/b.rb"])
      used = tests_the_run_used { run_engine({ "since" => "origin/main" }, true) }
      expect(used).to eq(["a_spec.rb"])
      expect(err.string).to include("no spec is required for lib/b.rb: intentionally untested")
      expect(err.string).to include("running only a_spec.rb")
    end

    # The map is read from disk once per run and shared with guessing and
    # subject selection (#369 review dogfood).
    it "loads the custom map once per run" do
      guess(specs: ["a_spec.rb"], unmatched: [], changed: 1)
      allow(Saboteur::CustomMap).to receive(:load).and_call_original
      run_engine("since" => "origin/main")
      expect(Saboteur::CustomMap).to have_received(:load).once
    end

    # Two excluded files read as a sentence, not a concatenation (#376 dogfood).
    it "separates excluded files with a comma in the note" do
      guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 2, excluded: ["lib/a.rb", "lib/b.rb"])
      run_engine("since" => "origin/main")
      expect(err.string).to include("no spec is required for lib/a.rb, lib/b.rb:")
    end

    it "names map-excluded files and runs nothing instead of the whole suite" do
      guess(specs: [], unmatched: [], changed: 1, excluded: ["lib/b.rb"])
      used = tests_the_run_used { run_engine("since" => "origin/main") }
      expect(used).to eq([])
      expect(err.string).to include("inferred specs: no spec is required for lib/b.rb: " \
                                    "intentionally untested in config/saboteur_custom_map.rb, " \
                                    "so there is nothing to mutate")
      expect(err.string).not_to include("running only")
      # The empty-specs path says it once, inside the nothing-to-mutate note:
      # the excluded note before announce must stay quiet there (#376 dogfood).
      expect(err.string.scan("no spec is required for lib/b.rb").size).to eq(1)
    end

    it "says there is nothing to mutate when no changed file has a mutation subject" do
      guess(specs: [], unmatched: [], changed: 1, subjectless: ["lib/errors.rb"])
      used = tests_the_run_used { run_engine("since" => "origin/main") }
      expect(used).to eq([])
      expect(@engine.guessed_tests).to be_nil
      expect(err.string).to include("inferred specs: no changed file has a mutation subject on its changed lines, " \
                                    "so there is nothing to mutate")
      expect(err.string).to include("no spec is required for lib/errors.rb: it has no changed mutation subjects")
      expect(err.string).not_to include("the whole suite runs")
    end

    it "notes nothing to mutate once, keeping the sentence out of the report warnings (#468)" do
      guess(specs: [], unmatched: [], changed: 1, subjectless: ["lib/errors.rb"])
      report = run_engine("since" => "origin/main")
      expect(err.string.scan("no changed file has a mutation subject on its changed lines").size).to eq(1)
      expect(report.warnings.grep(/nothing to mutate/)).to be_empty
    end

    it "notes nothing to mutate once without --since too (#468)" do
      guess(specs: [], unmatched: [], changed: 2, subjectless: ["lib/a.rb"])
      report = run_engine({})
      expect(err.string.scan("no source file has a mutation subject").size).to eq(1)
      expect(report.warnings.grep(/nothing to mutate/)).to be_empty
    end

    it "notes skipped subjectless files while scoping to the inferred specs" do
      guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 2, subjectless: ["lib/errors.rb"])
      used = tests_the_run_used { run_engine({ "since" => "origin/main" }, true) }
      expect(used).to eq(["spec/a_spec.rb"])
      expect(err.string).to include("inferred specs: running only spec/a_spec.rb")
      expect(err.string).to include("no spec is required for lib/errors.rb")
    end

    it "stops and names changed source files outside the include scope (#483)" do
      guess(specs: [], unmatched: [], changed: 0, out_of_scope: ["engines/billing/lib/billing.rb"])
      expect { run_engine("since" => "origin/main") }
        .to raise_error(Saboteur::ConfigError,
                        %r{no changed source file lies inside the include scope.*engines/billing/lib/billing\.rb}m)
      expect(Saboteur::Engine::CoverageStore).not_to have_received(:new)
    end

    it "does not stop when an included file changed even if out-of-scope files are listed (#483)" do
      guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 1, out_of_scope: ["engines/billing/lib/billing.rb"])
      expect { run_engine({ "since" => "origin/main" }, true) }.not_to raise_error
      expect(err.string).to include("inferred specs: running only spec/a_spec.rb")
    end

    it "points at include and --test, never a reconstructed command carrying the ref" do
      guess(specs: [], unmatched: [], changed: 0, out_of_scope: ["engines/billing/lib/billing.rb"])
      expect { run_engine("since" => "weird ref;$(rm -rf)") }
        .to raise_error(Saboteur::ConfigError) do |error|
        expect(error.message).not_to include("weird ref")
        expect(error.message).to include("Extend include to cover them")
        expect(error.message).to include("one --test per existing spec path")
      end
    end

    it "says why no spec was inferred when --since leaves no changed source file (#607, #1232)" do
      guess(specs: [], unmatched: [], changed: 0)
      run_engine("since" => "origin/main")
      expect(err.string).to include("inferred specs: no changed source file to infer a spec for\n")
      expect(err.string).not_to include("the whole suite runs")
      # The conclusion is stated once, by the outcome line (#1232); this
      # harness stops before it, so the phrase must not appear here at all.
      expect(err.string).not_to include("nothing to test")
    end

    it "names every subjectless file in the note" do
      guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 3, subjectless: ["lib/b.rb", "lib/c.rb"])
      run_engine("since" => "origin/main")
      expect(err.string).to include("no spec is required for lib/b.rb, lib/c.rb:")
    end

    it "infers specs from the configured sources without --since" do
      guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 1)
      used = tests_the_run_used { run_engine({}, true) }
      expect(used).to eq(["spec/a_spec.rb"])
      expect(err.string).to include("inferred specs: running only spec/a_spec.rb")
      expect(err.string).not_to include("running the loaded suite unscoped")
    end

    it "gives an append-only recovery instruction, never a reconstructed command carrying the ref" do
      guess(specs: [], unmatched: ["lib/b.rb"], changed: 1)
      expect { run_engine({}) }
        .to raise_error(Saboteur::ConfigError, /append --all to use the whole suite without changing the source scope/)
      ["origin/main", "-rf"].each do |ref|
        expect { run_engine("since" => ref) }
          .to raise_error(Saboteur::ConfigError,
                          /Re-run the same command with one --test per existing spec path/)
      end
      expect { run_engine("since" => "weird ref;$(rm -rf)") }
        .to raise_error(Saboteur::ConfigError) { |error| expect(error.message).not_to include("weird ref") }
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

  describe "--subject runs" do
    # The exclusion note fires in a --subject run only when the guess
    # actually excluded files (#369 review dogfood).
    it "names excluded files in a --subject run" do
      write_subject_project
      guess(specs: ["spec/people_spec.rb"], unmatched: [], changed: 1, excluded: ["lib/b.rb"])
      used = tests_the_run_used { run_engine("subjects" => ["Person#adult?"]) }
      expect(used).to eq(["spec/people_spec.rb"])
      expect(err.string).to include("no spec is required for lib/b.rb: intentionally untested")
    end

    it "prints no exclusion note in a --subject run without excluded files" do
      write_subject_project
      guess(specs: ["spec/people_spec.rb"], unmatched: [], changed: 1)
      tests_the_run_used { run_engine("subjects" => ["Person#adult?"]) }
      expect(err.string).not_to include("intentionally untested")
    end

    # Every in-scope file intentionally untested: the --subject run mutates
    # nothing and never announces a guessed selection (#369 review dogfood).
    it "runs nothing in a --subject run when every file is map-excluded" do
      write_subject_project
      guess(specs: [], unmatched: [], changed: 1, excluded: ["lib/b.rb"])
      used = tests_the_run_used { run_engine("subjects" => ["Person#adult?"]) }
      expect(used).to eq([])
      expect(err.string).to include("intentionally untested")
      expect(err.string).not_to include("running only")
    end

    def write_subject_project(with_spec: true)
      FileUtils.mkdir_p(File.join(@root, "lib"))
      File.write(File.join(@root, "lib", "people.rb"), "class Person\n  def adult?\n    true\n  end\nend\n")
      File.write(File.join(@root, "lib", "other.rb"), "class Other\n  def x\n    1\n  end\nend\n")
      return unless with_spec

      FileUtils.mkdir_p(File.join(@root, "spec"))
      File.write(File.join(@root, "spec", "people_spec.rb"), "# spec\n")
    end

    it "infers only the named subject's spec, ignoring unrelated spec-less files" do
      write_subject_project
      allow(Saboteur::Engine::TestGuess).to receive(:new).and_call_original
      used = tests_the_run_used { run_engine("subjects" => ["Person#adult?"]) }
      expect(used).to eq(["spec/people_spec.rb"])
      expect(err.string).to include("inferred specs: running only spec/people_spec.rb")
      expect(Saboteur::Engine::TestGuess).to have_received(:new)
        .with(an_instance_of(Saboteur::Config), diagnostics: @engine.instance_variable_get(:@diagnostics),
                                                custom_map: an_instance_of(Saboteur::CustomMap))
    end

    # P5 (#1316): under --quiet the two-line inference notice stays off
    # stderr; it remains a report warning for machine consumers.
    it "hides the inferred-specs notice under --quiet, keeping it as a report warning" do
      write_subject_project
      guess(specs: ["spec/people_spec.rb"], unmatched: [], changed: 1)
      stub_boot_phase
      stub_test_phases
      @engine = described_class.new(Saboteur::Config.new({ "jobs" => 2, "subjects" => ["Person#adult?"] },
                                                         root: @root),
                                    err: err, quiet: true)
      @report = @engine.call
      expect(err.string).not_to include("inferred specs")
      expect(@report.warnings).to include(a_string_starting_with("inferred specs: running only spec/people_spec.rb"))
    end

    it "names the spec files the diff deleted in a --subject run (#307)" do
      write_subject_project
      guess(specs: %w[spec/people_spec.rb], unmatched: [], changed: 1,
            skipped_specs: { "spec/old_spec.rb" => "deleted in the diff" })
      tests_the_run_used { run_engine("since" => "HEAD", "subjects" => ["Person#adult?"]) }
      expect(err.string).to include("not running spec files changed in the diff: " \
                                    "spec/old_spec.rb (deleted in the diff)")
    end

    it "names the skipped spec files before stopping on an unmatched file (#307)" do
      guess(specs: [], unmatched: ["lib/c.rb"], changed: 1,
            skipped_specs: { "spec/requests/status_spec.rb" => "deleted in the diff" })
      expect { run_engine("since" => "origin/main") }.to raise_error(Saboteur::ConfigError, /no spec found/)
      expect(err.string).to include("not running spec files changed in the diff: " \
                                    "spec/requests/status_spec.rb (deleted in the diff)")
    end

    it "stops before boot when the named subject's own file has no spec" do
      write_subject_project(with_spec: false)
      expect { run_engine("subjects" => ["Person#adult?"]) }
        .to raise_error(Saboteur::ConfigError,
                        %r{no spec found for lib/people\.rb \(expected spec/people_spec\.rb\), so nothing ran})
      expect(Saboteur::Engine::CoverageStore).not_to have_received(:new)
    end

    it "skips inference when no included file holds the named subject" do
      write_subject_project
      tests_the_run_used { run_engine("subjects" => ["Nope#nothing"]) }
      expect(err.string).not_to include("inferred specs:")
    end

    it "ignores named subjects outside the --since diff scope instead of stopping" do
      write_subject_project(with_spec: false)
      allow(Saboteur::Selection::GitDiff).to receive(:changed_lines).and_return({})
      allow(Saboteur::Selection::GitDiff).to receive(:merge_base).and_return("HEAD")
      used = tests_the_run_used { run_engine("since" => "HEAD", "subjects" => ["Person#adult?"]) }
      expect(used).to eq([])
      expect(err.string).not_to include("inferred specs:")
    end

    it "stops before boot when the named subject sits on a changed line and has no spec" do
      write_subject_project(with_spec: false)
      people = File.join(@root, "lib", "people.rb")
      allow(Saboteur::Selection::GitDiff).to receive(:changed_lines).and_return({ people => Set[3] })
      allow(Saboteur::Selection::GitDiff).to receive(:merge_base).and_return("HEAD")
      allow(Saboteur::Selection::GitDiff).to receive(:changed_paths).and_return(present: [], deleted: [])
      comparison = instance_double(Saboteur::Engine::UnchangedSyntax, unchanged?: false)
      allow(Saboteur::Engine::UnchangedSyntax).to receive(:new).and_return(comparison)
      expect { run_engine("since" => "HEAD", "subjects" => ["Person#adult?"]) }
        .to raise_error(Saboteur::ConfigError, %r{no spec found for lib/people\.rb})
    end

    it "keeps the recorded tests in replay mode, skipping inference" do
      engine = described_class.new(Saboteur::Config.new({}, root: @root), err: err, digest: "0" * 16)
      expect(Saboteur::Engine::TestGuess).not_to receive(:new)
      engine.send(:select_tests)
    end
  end

  it "does not infer when --test scopes the specs" do
    allow(Saboteur::Engine::TestGuess).to receive(:new)
    run_engine("since" => "origin/main", "tests" => ["a_spec.rb"])
    expect(Saboteur::Engine::TestGuess).not_to have_received(:new)
    expect(err.string).not_to include("running the loaded suite unscoped")
  end

  it "warns about the unscoped suite with only --all" do
    used = tests_the_run_used { run_engine("all" => true) }
    expect(used).to eq([])
    expect(err.string).to include("running the loaded suite unscoped")
  end

  it "warns about the unscoped suite with only c.test_selection = :all" do
    used = tests_the_run_used { run_engine("test_selection" => "all") }
    expect(used).to eq([])
    expect(err.string).to include("running the loaded suite unscoped")
  end

  it "warns about the unscoped suite with only --since when nothing is left to infer from" do
    guess(specs: [], unmatched: [], changed: 0)
    used = tests_the_run_used { run_engine("since" => "origin/main") }
    expect(used).to eq([])
    expect(err.string).to include("inferred specs: no changed source file to infer a spec for\n")
    expect(err.string).to include("running the loaded suite unscoped")
  end

  it "keeps the nothing-to-test note a report warning when nothing changed (#468)" do
    guess(specs: [], unmatched: [], changed: 0)
    report = run_engine("since" => "origin/main")
    expect(report.warnings)
      .to include("inferred specs: no changed source file to infer a spec for")
  end

  it "names the no-source-file case without --since" do
    guess(specs: [], unmatched: [], changed: 0)
    used = tests_the_run_used { run_engine({}) }
    expect(used).to eq([])
    expect(err.string).to include("inferred specs: no source file to infer a spec for, so the whole suite runs")
  end

  it "names the no-mutation-subject case without --since" do
    guess(specs: [], unmatched: [], changed: 2, subjectless: ["lib/a.rb"])
    used = tests_the_run_used { run_engine({}) }
    expect(used).to eq([])
    expect(err.string).to include(
      "inferred specs: no source file has a mutation subject, so there is nothing to mutate"
    )
  end

  it "says a changed file with --since and a source file without in the inference warning" do
    guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 1)
    run_engine({ "since" => "origin/main" }, true)
    expect(err.string).to include("A spec the diff did not change that reaches a changed file only through " \
                                  "another file does not run")
    guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 1)
    run_engine({}, true)
    expect(err.string).to include("A spec that reaches a source file only through another file does not run")
  end

  it "drops guess_tests from the scoped config so the deprecated opt-out does not warn again" do
    guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 1)
    tests_the_run_used { run_engine("since" => "origin/main", "guess_tests" => false) }
    expect(@scoped_config.deprecation_warnings).to be_empty
  end

  it "says nothing about the suite when inference narrows without --since" do
    guess(specs: ["spec/a_spec.rb"], unmatched: [], changed: 1)
    run_engine({})
    expect(err.string).not_to include("running the loaded suite unscoped")
  end
end

RSpec.describe Saboteur::Engine, "--subject inference with a constant-only file (#319 dogfood)" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  # Under --since the constant fallback in files_matching needs the run's
  # config; without it a file holding only the named constant falls out of
  # inference and the run would scope to nothing.
  it "infers specs from a file holding only the named constant" do
    FileUtils.mkdir_p(File.join(@root, "lib"))
    File.write(File.join(@root, "lib", "rules.rb"), "RULES = { a: 1 }.freeze\n")
    result = Saboteur::Engine::TestGuess::Result.new(specs: ["spec/rules_spec.rb"], unmatched: [],
                                                     subjectless: [], changed: 1, hints: [])
    guess = instance_double(Saboteur::Engine::TestGuess)
    allow(Saboteur::Engine::TestGuess).to receive(:new).and_return(guess)
    allow(guess).to receive(:call_for).and_return(result)
    sentinel = Class.new(StandardError)
    # The recursion guard fires first inside a saboteur child (the dogfood
    # baseline run); the boot stub is what this example actually drives at.
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    allow(Saboteur::Engine::Boot).to receive(:new).and_raise(sentinel)

    config = Saboteur::Config.new({ "since" => "HEAD", "subjects" => ["RULES"] }, root: @root)
    expect { described_class.new(config, err: StringIO.new).call }.to raise_error(sentinel)
    expect(guess).to have_received(:call_for).with(["lib/rules.rb"], ["RULES"])
  end
end
