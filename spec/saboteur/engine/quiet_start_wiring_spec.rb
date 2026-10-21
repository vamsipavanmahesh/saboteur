# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# Engine-level wiring for the quiet start (PR4). quiet_start_pins_spec proves
# the three lines render; these specs prove a real run calls them - header
# before the baseline, then the baseline+coverage line, then the inference
# count - and that --verbose and the agent machine path (quiet_start: false)
# keep the pre-diet output byte-for-byte.
RSpec.describe Saboteur::Engine, "quiet start wiring" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
  end

  # The goldens pin the UTF-8 glyphs; force a UTF-8 locale so a
  # C-locale CI leg does not downgrade them to their ASCII fallbacks.
  around do |example|
    saved = ENV.to_h.slice("LC_ALL", "LC_CTYPE", "LANG")
    ENV["LC_ALL"] = "C.UTF-8"
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  ensure
    keys = %w[LC_ALL LC_CTYPE LANG]
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
  end

  let(:err) { StringIO.new }
  let(:subject_under_test) do
    subjects_in("class SinceTarget\n  def m\n    1\n  end\nend\n", name: "since_target.rb").first
  end
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => ["t1"] } }, tests: ["t1"])
  end
  let(:integration) do
    instance_double(Saboteur::Integration::RSpec, test_files: %w[spec/since_target_spec.rb],
                                                  all_tests: [double(id: "t1")])
  end

  let(:header_re) do
    /saboteur #{Regexp.escape(Saboteur::VERSION)} · (?<scope>.*) · seed \d+ · \d+ operators \(--list-operators\)\n/
  end
  let(:baseline_re) { /✓ baseline green \(2 passes, \d+\.\ds\)  ✓ coverage map: 1 test(?<cached> \(cached\))?\n/ }
  let(:old_map_line) { "1 subjects, 1 tests in coverage map" }
  let(:inferred_line) { "spec inference: 1 spec file (details: --verbose)" }
  let(:inferred_paragraph) { "inferred specs: running only spec/since_target_spec.rb." }

  def run_engine(overrides, verbose: false, quiet_start: true, reusable: false, changed: 0, specs: [])
    stub_boot_phase
    stub_test_phases(reusable: reusable)
    stub_guess(changed: changed, specs: specs)
    engine = described_class.new(Saboteur::Config.new({ "jobs" => 2 }.merge(overrides), root: @root),
                                 err: err, verbose: verbose, quiet_start: quiet_start)
    engine.call
    err.string
  end

  def stub_boot_phase
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject_under_test], behavior_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  def stub_test_phases(reusable:)
    baseline = instance_double(Saboteur::Engine::BaselineGuard, completed_passes: 2)
    allow(baseline).to receive(:call) { err.puts("saboteur: checking the unchanged suite twice (seed 1)") }
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: reusable)
    allow(store).to receive(:fetch).and_return(map)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    distribution = instance_double(Saboteur::Engine::Distribution, memory_report: nil, run: [], unreached: [],
                                                                   truncated: [], unverified: [])
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
  end

  def stub_guess(changed:, specs:)
    result = Saboteur::Engine::TestGuess::Result.new(specs: specs, unmatched: [], subjectless: [], changed: changed,
                                                     hints: {}, changed_specs: [], skipped_specs: {},
                                                     out_of_scope: [], excluded: [], no_suite: nil, referenced: {})
    allow(Saboteur::Engine::TestGuess).to receive(:new).and_return(instance_double(Saboteur::Engine::TestGuess,
                                                                                   call: result, call_for: result))
  end

  it "opens a default whole-project run with the quiet header and baseline lines, nothing else revived" do
    out = run_engine({})
    expect(out.match(header_re)[:scope]).to eq("whole project")
    expect(out).to match(baseline_re)
    expect(out).not_to include("(cached)")
    expect(out).not_to include("spec inference:")
    expect(out).not_to include(old_map_line)
  end

  it "prints the diff scope in the header and folds the inference paragraph into the count line" do
    out = run_engine({ "since" => "HEAD~1" }, changed: 1, specs: ["spec/since_target_spec.rb"])
    expect(out.match(header_re)[:scope]).to eq("--since HEAD~1")
    expect(out).to include(inferred_line)
    expect(out).not_to include(inferred_paragraph)
  end

  it "reports zero passes when the baseline never ran" do
    engine = described_class.new(Saboteur::Config.new({ "jobs" => 2 }, root: @root), err: err)
    engine.send(:inform_about_run, [], map)
    expect(err.string).to include("0 passes, 0.0s")
  end

  it "marks a cached coverage map" do
    expect(run_engine({}, reusable: true).match(baseline_re)[:cached]).to eq(" (cached)")
  end

  it "keeps the pre-diet output under --verbose" do
    out = run_engine({ "since" => "HEAD~1" }, verbose: true,
                                              changed: 1, specs: ["spec/since_target_spec.rb"])
    expect(out).to include(inferred_paragraph)
    expect(out).to include(old_map_line)
    expect(out).not_to match(header_re)
    expect(out).not_to include("spec inference:")
  end

  it "keeps the pre-diet default output on the agent machine path (quiet_start: false)" do
    out = run_engine({ "since" => "HEAD~1" }, quiet_start: false,
                                              changed: 1, specs: ["spec/since_target_spec.rb"])
    expect(out).to include(inferred_paragraph)
    expect(out).to include(old_map_line)
    expect(out).not_to match(header_re)
    expect(out).not_to include("spec inference:")
  end
end
