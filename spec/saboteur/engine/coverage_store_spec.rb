# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "fileutils"
require "tmpdir"

RSpec.describe Saboteur::Engine::CoverageStore do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  before { allow(Saboteur::CoverageReads).to receive(:result).and_return({}) }

  let(:file) { File.join(@root, "a.rb").tap { |path| File.write(path, "1\n") } }
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: []) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }
  let(:map) { Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"]) }

  def store(load_lines: {}, **settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                        load_lines: load_lines)
  end

  def built_result(payload)
    Saboteur::Execution::Supervisor::Result.new(payload: payload, exit_status: nil, stopped_by: nil,
                                                detail: nil, runtime: 0.1, leftover_pids: [])
  end

  # Survivor kill for #480's load tracking (#480 dogfood gate).
  it "merges parent load methods into the map even when load lines are empty" do
    store = store()
    store.instance_variable_set(:@load_methods, file => [2])
    merged = store.send(:with_parent_load_lines, map)
    expect(merged).not_to equal(map)
    expect(merged.load_methods).to eq(file => [2])
  end

  def cache_files
    Dir[File.join(@root, ".saboteur", "coverage-*.json")]
  end

  it "raises BudgetPhaseTimeout when a budget-capped build hits its shortened deadline (#296)" do
    allow(Coverage).to receive(:state).and_return(:suspended)
    stopped = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :timeout,
                                                          detail: "exceeded deadline", runtime: 0.1,
                                                          leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(stopped)
    capped = described_class.new(config: Saboteur::Config.new({}, root: @root), integration: integration,
                                 hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                 diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                 timeout_cap: ->(timeout) { timeout / 2 })
    expect { capped.fetch([file]) }.to raise_error(Saboteur::BudgetPhaseTimeout,
                                                   "the --max-duration budget stopped the coverage map build " \
                                                   "(admitted 1800.0s of the 3600.0s phase timeout)")
  end

  it "still fails the build when a capped run stops for a non-timeout reason (memory) even shortened (#296)" do
    allow(Coverage).to receive(:state).and_return(:suspended)
    stopped = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :memory,
                                                          detail: "over 512 MB", runtime: 0.1, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(stopped)
    capped = described_class.new(config: Saboteur::Config.new({}, root: @root), integration: integration,
                                 hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                 diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                 timeout_cap: ->(timeout) { timeout / 2 })
    expect { capped.fetch([file]) }.to raise_error(Saboteur::Error, "coverage map build stopped: over 512 MB")
  end

  it "still fails the build when a timeout hits a full-length admission: cap present but not shortening (#296)" do
    allow(Coverage).to receive(:state).and_return(:suspended)
    stopped = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :timeout,
                                                          detail: "exceeded deadline", runtime: 0.1,
                                                          leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(stopped)
    uncapped = described_class.new(config: Saboteur::Config.new({}, root: @root), integration: integration,
                                   hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                   diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                   timeout_cap: ->(timeout) { timeout })
    expect { uncapped.fetch([file]) }.to raise_error(Saboteur::Error, "coverage map build stopped: exceeded deadline")
  end

  it "still fails the build when a full-length admission times out: the suite, not the budget (control)" do
    allow(Coverage).to receive(:state).and_return(:suspended)
    stopped = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :timeout,
                                                          detail: "exceeded deadline", runtime: 0.1,
                                                          leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(stopped)
    expect { store.fetch([file]) }.to raise_error(Saboteur::Error, "coverage map build stopped: exceeded deadline")
  end

  it "merges the parent's load lines into the built map and caches them" do
    payload = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"]).to_json
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(supervisor).to receive(:run).and_return(built_result(payload))
    map = store(load_lines: { file => [2] }).fetch([file])
    expect(map.tests_for_lines(file, [1])).to eq(["t1"])
    expect(map.ran_at_load?(file, [2])).to be(true)
    cached = Saboteur::Selection::CoverageMap.load(cache_files.first)
    expect(cached.ran_at_load?(file, [2])).to be(true)
  end

  it "keeps the map object unchanged when there are no parent load lines" do
    expect(store.send(:with_parent_load_lines, map)).to equal(map)
  end

  it "records an auditable preview receipt next to a fresh map" do
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(supervisor).to receive(:run).and_return(built_result(map.to_json))
    store.fetch([file])
    receipt = JSON.parse(File.read(File.join(@root, ".saboteur", "preview.json")))
    expect(File.file?(receipt.fetch("path"))).to be(true)
    config = Saboteur::Config.new({}, root: @root)
    expect(receipt.fetch("fingerprint")).to eq(Saboteur::Engine::RunFingerprint.new(config: config).snapshot.digest)
  end

  it "reusable? is true for a clean saved map, and fetch then skips the build" do
    first = store
    allow(first).to receive(:build).and_return(map)
    first.fetch([file])

    second = store
    expect(second.reusable?([file])).to be(true)
    allow(second).to receive(:build)
    expect(second.fetch([file]).tests).to eq(["t1"])
    expect(second).not_to have_received(:build)
  end

  it "loads the cached map once across reusable? and fetch" do
    first = store
    allow(first).to receive(:build).and_return(map)
    first.fetch([file])

    second = store
    allow(Saboteur::Selection::CoverageMap).to receive(:load).and_call_original
    expect(second.reusable?([file])).to be(true)
    expect(second.fetch([file]).tests).to eq(["t1"])
    expect(Saboteur::Selection::CoverageMap).to have_received(:load).once
  end

  it "reusable? is false for a corrupt cache, so the run announces and pays the build pass (#260)" do
    corruptions = ["{ not json",
                   JSON.generate("format" => "nope", "tests" => [], "lines" => {}),
                   "prefix\xE4\x4Dinvalid".b]
    corruptions.each do |garbage|
      first = store
      allow(first).to receive(:build).and_return(map)
      first.fetch([file])
      File.binwrite(cache_files.first, garbage)

      second = store
      expect(second.reusable?([file])).to be(false)
      allow(second).to receive(:build).and_return(map)
      expect(second.fetch([file]).tests).to eq(["t1"])
      expect(second).to have_received(:build)
    end
  end

  it "builds once, saves, and reuses the cached map while inputs are unchanged" do
    first = store
    allow(first).to receive(:build).and_return(map)
    expect(first.fetch([file]).tests).to eq(["t1"])
    expect(cache_files.size).to eq(1)

    second = store
    allow(second).to receive(:build)
    expect(second.fetch([file]).tests).to eq(["t1"])
    expect(second).not_to have_received(:build)
  end

  it "rebuilds when a source file changes" do
    first = store
    allow(first).to receive(:build).and_return(map)
    first.fetch([file])
    File.write(file, "2\n")
    second = store
    allow(second).to receive(:build).and_return(map)
    second.fetch([file])
    expect(second).to have_received(:build)
    expect(cache_files.size).to eq(2)
  end

  # Support files, spec_helper and boot files decide which test runs which
  # line just as much as example files do.
  ["spec/support/helpers.rb", "spec/spec_helper.rb", ".rspec", "config/boot.rb", "config/saboteur_hooks.rb"]
    .each do |input|
      it "rebuilds when #{input} changes" do
        path = File.join(@root, input)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "1\n")
        settings = { "config/boot.rb" => { require: ["./config/boot"] },
                     "config/saboteur_hooks.rb" => { hooks: ["config/saboteur_hooks.rb"] } }.fetch(input, {})
        first = store(**settings)
        allow(first).to receive(:build).and_return(map)
        first.fetch([file])
        File.write(path, "2\n")
        second = store(**settings)
        allow(second).to receive(:build).and_return(map)
        second.fetch([file])
        expect(second).to have_received(:build)
      end
    end

  it "rebuilds when the lockfile changes" do
    lock = File.join(@root, "Gemfile.lock").tap { |p| File.write(p, "a\n") }
    store.tap { |s| allow(s).to receive(:build).and_return(map) }.fetch([file])
    File.write(lock, "b\n")
    again = store
    allow(again).to receive(:build).and_return(map)
    again.fetch([file])
    expect(again).to have_received(:build)
  end

  it "caps the supervised build at the time a timeout cap leaves (#296)" do
    built = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: built.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    capped = described_class.new(config: Saboteur::Config.new({}, root: @root), integration: integration,
                                 hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                 diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                 timeout_cap: ->(timeout) { timeout / 2 })
    capped.fetch([file])
    expect(supervisor).to have_received(:run).with(timeout: 1800.0, on_tick: anything,
                                                   label: "coverage child died during the map build")
  end

  it "builds the map in a supervised child and says so" do
    err = StringIO.new
    built = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: built.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    diagnostics = Saboteur::Engine::Diagnostics.new(err)
    heartbeat = Saboteur::Engine::Diagnostics::ProgressHeartbeat.new(diagnostics, "building coverage map")
    allow(heartbeat).to receive(:watch).and_call_original
    allow(diagnostics).to receive(:progress_heartbeat).and_return(heartbeat)
    store = described_class.new(config: Saboteur::Config.new({}, root: @root), integration: integration,
                                hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                diagnostics: diagnostics)
    expect(store.fetch([file]).tests).to eq(["t1"])
    expect(err.string).to include("building coverage map (runs the whole suite once)")
    expect(diagnostics).to have_received(:progress_heartbeat).with("building coverage map")
    expect(heartbeat).to have_received(:watch).with(File.join(@root, ".saboteur/coverage-build.log"))
    expect(supervisor).to have_received(:run).with(timeout: 3600.0, on_tick: anything,
                                                   label: "coverage child died during the map build")
  end

  # --test narrows the map build to the given specs; the message must say
  # so, or a user waits for the whole suite without knowing.
  it "says the map build runs only the selected specs when --test narrowed the suite" do
    err = StringIO.new
    built = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: built.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    store = described_class.new(config: Saboteur::Config.new({ "tests" => ["spec/one_spec.rb"] }, root: @root),
                                integration: integration, hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                diagnostics: Saboteur::Engine::Diagnostics.new(err))
    store.fetch([file])
    expect(err.string).to include("building coverage map (runs the selected specs once)")
  end

  # First-run notices (#1264): the miss line and the build line, in the
  # whole-suite and --test wordings, off with cache: false and under --quiet.
  describe "first-run notices (#1264)" do
    let(:built) { Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"]) }
    let(:ok) do
      Saboteur::Execution::Supervisor::Result.new(payload: built.to_json, exit_status: nil, stopped_by: nil,
                                                  detail: nil, runtime: 1.0, leftover_pids: [])
    end

    before do
      allow(supervisor).to receive(:run).and_return(ok)
      allow(Coverage).to receive(:state).and_return(:suspended)
    end

    def fetch_with(settings = {}, quiet: false)
      err = StringIO.new
      config = Saboteur::Config.new(settings, root: @root)
      described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                          supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err, quiet: quiet))
                     .fetch([file])
      err.string
    end

    it "explains a whole-suite miss with the hint, and a --test miss without it" do
      whole = fetch_with
      expect(whole).to include("saboteur: coverage cache miss: no earlier map to compare with; " \
                               "the map build runs the whole suite once")
      expect(whole).to include(Saboteur::Engine::CoverageMissNote::HINT)
      FileUtils.rm_rf(File.join(@root, ".saboteur"))
      scoped = fetch_with({ "tests" => ["spec/one_spec.rb"] })
      expect(scoped).to include("the map build runs the selected specs once")
      expect(scoped).not_to include(Saboteur::Engine::CoverageMissNote::HINT)
    end

    it "prints no miss line with cache: false, and no notices at all under --quiet" do
      expect(fetch_with({ "cache" => false })).not_to include("coverage cache miss")
      FileUtils.rm_rf(File.join(@root, ".saboteur"))
      expect(fetch_with({}, quiet: true)).to eq("")
    end

    it "says how many parallel parts build the map" do
      allow(integration).to receive(:test_files).and_return(%w[/s/a_spec.rb /s/b_spec.rb /s/c_spec.rb])
      allow(integration).to receive(:example_count).and_return(1)
      allow(integration).to receive(:example_count).with(no_args).and_return(3)
      results = %w[t1 t2 t3].map do |name|
        map = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => [name] } }, tests: [name])
        Saboteur::Execution::Supervisor::Result.new(payload: map.to_json, exit_status: nil, stopped_by: nil,
                                                    detail: nil, runtime: 1.0, leftover_pids: [])
      end
      allow(supervisor).to receive(:run_many).and_return(results)
      err = StringIO.new
      described_class.new(config: Saboteur::Config.new({}, root: @root), integration: integration,
                          hooks: Saboteur::Hooks.new, supervisor: supervisor,
                          diagnostics: Saboteur::Engine::Diagnostics.new(err), parts: 3).fetch([file])
      expect(err.string).to include("building coverage map (runs the suite once, in 3 parallel parts)")
    end

    it "says how many saved parts a rebuild reuses" do
      allow(integration).to receive(:test_files).and_return(%w[/s/a_spec.rb /s/b_spec.rb /s/c_spec.rb])
      allow(integration).to receive(:example_count).and_return(1)
      allow(integration).to receive(:example_count).with(no_args).and_return(3)
      maps = %w[t1 t2 t3].map do |name|
        Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => [name] } }, tests: [name])
      end
      err = StringIO.new
      store = described_class.new(config: Saboteur::Config.new({}, root: @root), integration: integration,
                                  hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                  diagnostics: Saboteur::Engine::Diagnostics.new(err), parts: 3)
      allow(store).to receive_messages(saved_parts: [maps[0], nil, nil], run_parts: maps.drop(1))
      store.fetch([file])
      expect(err.string).to include("building coverage map (runs the suite once, in 3 parallel parts, reusing 1 saved)")
    end
  end

  # A child that dies before reporting (a crash in a native extension, an
  # exit! in the suite) must leave enough to find out why.
  [[{ signaled?: true, termsig: 11 }, "was killed by signal SEGV"],
   [{ signaled?: false, exitstatus: 2 }, "exited with status 2"]].each do |status, how|
    it "says how the coverage child ended when it #{how} without a result" do
      died = Saboteur::Execution::Supervisor::Result.new(
        payload: "", exit_status: instance_double(Process::Status, **status), stopped_by: nil,
        detail: nil, runtime: 1.0, leftover_pids: []
      )
      allow(supervisor).to receive(:run).and_return(died)
      allow(Coverage).to receive(:state).and_return(:suspended)
      expect { store.fetch([file]) }.to raise_error(
        Saboteur::Error, "coverage map build failed: the suite #{how} before reporting; " \
                         "its output is in .saboteur/coverage-build.log"
      )
    end
  end

  # Bootsnap's compile cache is the common cause, but whatever hides every
  # included file from Coverage must stop the run: the map would skip every
  # subject as "no coverage" and exit 0 (field report, issue 2).
  it "refuses a map with no lines for any included file and does not cache it" do
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: empty.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    expect { store.fetch([file]) }.to raise_error(
      Saboteur::Error,
      "Coverage recorded nothing in 1 included files during a whole-suite build. No test in the suite " \
      "may exercise these files, or the setup hid the app from Coverage. Run `saboteur doctor`."
    )
    expect(cache_files).to be_empty
  end

  it "names Bootsnap as a possible cause only when Bootsnap is loaded" do
    stub_const("Bootsnap", Module.new)
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: empty.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)

    expect { store.fetch([file]) }.to raise_error(
      Saboteur::Error, /Coverage \(Bootsnap's compile cache is the default Rails case\)\. Run/
    )
  end

  # An empty map cached by an older saboteur must not keep a run green.
  it "refuses a restored cached map with no lines for any included file" do
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    allow(Saboteur::Selection::CoverageMap).to receive(:load).and_return(empty)
    allow(Coverage).to receive(:state).and_return(:suspended)
    expect { store.fetch([file]) }.to raise_error(Saboteur::Error, /Coverage recorded nothing in 1 included files/)
  end

  # Endless defs record method calls but no line hits; that map is usable.
  it "accepts a map that recorded only method calls, the endless-def case" do
    method_only = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"], methods: { file => { 3 => ["t1"] } })
    result = Saboteur::Execution::Supervisor::Result.new(payload: method_only.to_json, exit_status: nil,
                                                         stopped_by: nil, detail: nil, runtime: 1.0,
                                                         leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    expect { store.fetch([file]) }.not_to raise_error
  end

  # "No coverage" can be spelled per-file hashes with no line entries, not
  # only a literally empty map.
  it "refuses a map whose per-file entries hold no covered lines" do
    hollow = Saboteur::Selection::CoverageMap.new(lines: { file => {} }, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: hollow.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    expect { store.fetch([file]) }.to raise_error(Saboteur::Error, /Coverage recorded nothing in 1 included files/)
    expect(cache_files).to be_empty
  end

  # With --test the preloaded refusal softens to a warning: the user
  # narrowed the suite on purpose, so the run continues with the subjects
  # classified "loaded before coverage started".
  it "warns and continues when a preloaded file empties the map but explicit tests narrowed the suite" do
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    allow(supervisor).to receive(:run).and_return(built_result(empty.to_json))
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Saboteur::Engine::LoadCoverage).to receive(:preloaded_uninstrumented).and_return([file])
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    config = Saboteur::Config.new({ "tests" => ["spec/stage_spec.rb"] }, root: @root)
    store = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: diagnostics)

    expect(store.fetch([file]).tests).to eq(["t1"])
    expect(diagnostics.warnings.join).to include("a.rb can never be covered: loaded before saboteur started coverage")
    # The preloaded warning must be the only one: falling through to the
    # generic "selected specs may not exercise them" warning would blame a
    # setup defect on the --test narrowing (#688).
    expect(diagnostics.warnings.size).to eq(1)
    expect(diagnostics.warnings.join).not_to include("the selected specs may not exercise them")
  end

  it "names the first five preloaded files with a tail" do
    files = %w[a.rb b.rb c.rb d.rb e.rb f.rb].map { |name| File.join(@root, name).tap { |p| File.write(p, "1\n") } }
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    allow(supervisor).to receive(:run).and_return(built_result(empty.to_json))
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Saboteur::Engine::LoadCoverage).to receive(:preloaded_uninstrumented).and_return(files)

    expect { store.fetch(files) }.to raise_error(
      Saboteur::Error,
      "a.rb, b.rb, c.rb, d.rb, e.rb and 1 more can never be covered: loaded before saboteur started coverage\n  " \
      "a require ran before the executable's Coverage.start, commonly the gemspec requiring the " \
      "library while bundler/setup evaluates it, or RUBYOPT -r\n  " \
      "Let the test suite load these files; a gemspec should require only its version file."
    )
  end

  it "names all five preloaded files without a tail at the boundary" do
    files = %w[a.rb b.rb c.rb d.rb e.rb].map { |name| File.join(@root, name).tap { |p| File.write(p, "1\n") } }
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    allow(supervisor).to receive(:run).and_return(built_result(empty.to_json))
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Saboteur::Engine::LoadCoverage).to receive(:preloaded_uninstrumented).and_return(files)

    expect { store.fetch(files) }.to raise_error(
      Saboteur::Error,
      "a.rb, b.rb, c.rb, d.rb, e.rb can never be covered: loaded before saboteur started coverage\n  " \
      "a require ran before the executable's Coverage.start, commonly the gemspec requiring the " \
      "library while bundler/setup evaluates it, or RUBYOPT -r\n  " \
      "Let the test suite load these files; a gemspec should require only its version file."
    )
  end

  it "names one preloaded file alone" do
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    allow(supervisor).to receive(:run).and_return(built_result(empty.to_json))
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Saboteur::Engine::LoadCoverage).to receive(:preloaded_uninstrumented).and_return([file])

    expect { store.fetch([file]) }.to raise_error(
      Saboteur::Error,
      "a.rb can never be covered: loaded before saboteur started coverage\n  " \
      "a require ran before the executable's Coverage.start, commonly the gemspec requiring the " \
      "library while bundler/setup evaluates it, or RUBYOPT -r\n  " \
      "Let the test suite load these files; a gemspec should require only its version file."
    )
  end

  # The files argument can spell a path through a symlink while the
  # preloaded list holds the canonical form; the refusal must still fire.
  it "refuses a preloaded file even when the run spells its path through a symlink" do
    File.symlink(@root, File.join(@root, "link"))
    spelled = File.join(@root, "link", "a.rb")
    hollow = Saboteur::Selection::CoverageMap.new(lines: { file => {} }, tests: ["t1"])
    allow(supervisor).to receive(:run).and_return(built_result(hollow.to_json))
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Saboteur::Engine::LoadCoverage).to receive(:preloaded_uninstrumented).and_return([file])

    expect do
      store.fetch([spelled])
    end.to raise_error(Saboteur::Error,
                       /a\.rb can never be covered: loaded before saboteur started coverage/)
  end

  # Spec files sit in the recorder's map, so a suite that tests nothing in
  # the included files still records its own spec code. The run must stop
  # even though the map as a whole is not empty.
  it "refuses a map that recorded only spec-file lines" do
    spec_only = Saboteur::Selection::CoverageMap.new(
      lines: { File.join(@root, "spec", "unrelated_spec.rb") => { 2 => ["t1"] } },
      tests: ["t1"]
    )
    allow(supervisor).to receive(:run).and_return(built_result(spec_only.to_json))
    allow(Coverage).to receive(:state).and_return(:suspended)
    expect { store.fetch([file]) }.to raise_error(Saboteur::Error, /Coverage recorded nothing in 1 included files/)
    expect(cache_files).to be_empty
  end

  # With --test the user narrowed the suite on purpose, and the chosen specs
  # may not touch the selected sources: an empty map is a legitimate "no
  # coverage" outcome there, not a broken setup.
  it "accepts an empty map when explicit tests narrowed the suite" do
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: empty.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    expect(store(tests: ["spec/stage_spec.rb"]).fetch([file]).tests).to eq(["t1"])
  end

  it "accepts an empty map when explicit tests came from the config file" do
    FileUtils.mkdir_p(File.join(@root, "config"))
    File.write(File.join(@root, "config", "saboteur.rb"),
               "Saboteur.configure { |c| c.tests = [\"spec/stage_spec.rb\"] }\n")
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: empty.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    yaml = Saboteur::Config.load(root: @root)
    store = described_class.new(config: yaml, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new))
    expect(store.fetch([file]).tests).to eq(["t1"])
  end

  it "accepts a cached empty map, with a warning, when explicit tests narrowed the suite" do
    err = StringIO.new
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    allow(Saboteur::Selection::CoverageMap).to receive(:load).and_return(empty)
    allow(Coverage).to receive(:state).and_return(:suspended)
    store = described_class.new(config: Saboteur::Config.new({ "tests" => ["spec/stage_spec.rb"] }, root: @root),
                                integration: integration, hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                diagnostics: Saboteur::Engine::Diagnostics.new(err))
    expect(store.fetch([file]).tests).to eq(["t1"])
    expect(store.instance_variable_get(:@diagnostics).warnings.last).to eq(
      "name the specs that exercise them in --test, or drop --test to run the whole suite\n  " \
      "Coverage recorded nothing in 1 included files; the selected specs may not exercise them."
    )
  end

  it "keeps the explicit-test and whole-suite caches separate" do
    first = store
    allow(first).to receive(:build).and_return(map)
    first.fetch([file])
    other = store(tests: ["spec/stage_spec.rb"])
    allow(other).to receive(:build).and_return(map)
    other.fetch([file])
    expect(cache_files.size).to eq(2)
  end

  it "accepts a map with no lines when nothing is included" do
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: empty.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    expect(store.fetch([]).tests).to eq(["t1"])
  end

  it "refuses to build when Coverage was not set up by the executable" do
    allow(Coverage).to receive(:state).and_return(:idle)
    expect { store.fetch([file]) }.to raise_error(Saboteur::Error, /SimpleCov/)
  end

  it "ignores the cache when caching is off" do
    store.tap { |s| allow(s).to receive(:build).and_return(map) }.fetch([file])
    uncached = store(cache: false)
    allow(uncached).to receive(:build).and_return(map)
    uncached.fetch([file])
    expect(uncached).to have_received(:build)
  end
end

RSpec.describe Saboteur::Engine::CoverageStore, "heap preparation" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  before { allow(Saboteur::CoverageReads).to receive(:result).and_return({}) }

  let(:file) { File.join(@root, "a.rb").tap { |path| File.write(path, "1\n") } }
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: []) }
  let(:map) { Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"]) }

  def store(supervisor)
    config = Saboteur::Config.new({ "coverage_timeout" => 60 }, root: @root)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new))
  end

  def recording_supervisor(events, payload)
    Class.new do
      define_method(:run) do |**|
        events << :fork
        Saboteur::Execution::Supervisor::Result.new(payload: payload, exit_status: nil, stopped_by: nil,
                                                    detail: nil, runtime: 0.0, leftover_pids: [])
      end
    end.new
  end

  # The coverage child inherits the parent's heap, so the store must prepare
  # that heap before the fork, not after.
  it "prepares the heap once, before forking the coverage child" do
    events = []
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap) { events << :prepare }
    # fetch's coverage guard expects the saboteur executable's setup.
    allow(Coverage).to receive(:state).and_return(:suspended)
    store(recording_supervisor(events, map.to_json)).fetch([file])
    expect(events).to eq(%i[prepare fork])
  end

  # A cached map means no child forks, so there is nothing to prepare for.
  it "does not prepare on a cache hit" do
    allow(Coverage).to receive(:state).and_return(:suspended)
    events = []
    store(recording_supervisor(events, map.to_json)).fetch([file])
    events.clear
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap) { events << :prepare }
    store(recording_supervisor(events, map.to_json)).fetch([file])
    expect(events).to be_empty
  end
  # A run that cannot build coverage must fail before any preparation.
  it "does not prepare when the coverage precondition is unmet" do
    allow(Coverage).to receive(:state).and_return(:running)
    events = []
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap) { events << :prepare }
    expect { store(recording_supervisor(events, map.to_json)).fetch([file]) }
      .to raise_error(Saboteur::Error, /must set it up/)
    expect(events).to be_empty
  end
end

RSpec.describe Saboteur::Engine::CoverageStore, "suite return validation" do
  it "does not produce a coverage payload when the unchanged adapter reports failure" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({}, root: root)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
      expect(integration).to receive(:run_all).and_return(false)
      writer = StringIO.new
      recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      store = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                  supervisor: nil, diagnostics: nil)
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(store).to receive(:exit!)
      store.send(:record, writer, ["/root/lib/a.rb"])
      expect(JSON.parse(writer.string)["error"]).to include("unchanged suite failed", "seed 1")
    end
  end
end

RSpec.describe Saboteur::Engine::CoverageStore, "seeding the recording" do
  it "seeds Kernel with the configured seed, so the recording suite shuffles like the run" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({ "seed" => 5 }, root: root)
      integration = instance_double(Saboteur::Integration::RSpec, run_all: true, test_files: [])
      recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      store = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                  supervisor: nil, diagnostics: nil)
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(store).to receive(:exit!)
      allow(store).to receive(:write_map)
      allow(Kernel).to receive(:srand)

      store.send(:record, StringIO.new, ["/root/lib/a.rb"])

      expect(Kernel).to have_received(:srand).with(5)
    end
  end
end

RSpec.describe Saboteur::Engine::CoverageStore, "successful recording" do
  it "records every Ruby source the child loaded, canonical and UTF-8 strict (#353)" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({}, root: root)
      integration = instance_double(Saboteur::Integration::RSpec, run_all: true, test_files: [])
      recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
      captured = nil
      allow(recorder).to receive(:result) do |**kwargs|
        captured = kwargs
        Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"], loaded_files: kwargs[:loaded_files])
      end
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      store = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                  supervisor: nil, diagnostics: nil)
      writer = StringIO.new
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(store).to receive(:exit!)

      lib = File.join(root, "lib")
      FileUtils.mkdir_p(lib)
      lazy = File.join(lib, "lazy.rb")
      accented = File.join(lib, "héllo.rb")
      features = [
        lazy,
        "#{root}//lib/double.rb", # collapsed by canonicalization
        File.join(lib, "native.so"), # not Ruby
        "#{root}-sibling/lib/other.rb", # shares the root's prefix only
        "/outside/else.rb",                              # outside the project
        accented.dup.force_encoding(Encoding::US_ASCII)  # feature entries are filesystem-encoded
      ]
      $LOADED_FEATURES.push(*features)
      begin
        store.send(:record, writer, [])
      ensure
        features.each { |feature| $LOADED_FEATURES.delete(feature) }
      end

      expect(captured[:build_seconds]).to be_a(Float)
      expect(captured[:build_seconds]).to be_between(0, 60)
      expect(captured[:loaded_files]).to contain_exactly(lazy, File.join(lib, "double.rb"), accented)
      expect(captured[:loaded_files].last.encoding).to eq(Encoding::UTF_8)
      expect(JSON.parse(writer.string)["loaded_files"]).to contain_exactly(lazy, File.join(lib, "double.rb"), accented)
      expect(writer).to be_closed
    end
  end

  # A symlink on the root path (macOS /var -> /private/var, a tmpdir symlink)
  # gives the same directory two spellings: realpath resolves config.root,
  # while $LOADED_FEATURES keeps the spelling used at require time, which
  # realpath resolves only for files that still exist. Membership must
  # recognize both spellings or every loaded file is dropped.
  it "records sources loaded under a symlinked root spelling (#353)" do
    Dir.mktmpdir do |target|
      Dir.mktmpdir do |parent|
        root = File.join(parent, "project")
        File.symlink(target, root)
        config = Saboteur::Config.new({}, root: root)
        integration = instance_double(Saboteur::Integration::RSpec, run_all: true, test_files: [])
        recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
        captured = nil
        allow(recorder).to receive(:result) do |**kwargs|
          captured = kwargs
          Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"], loaded_files: kwargs[:loaded_files])
        end
        allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
        store = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                    supervisor: nil, diagnostics: nil)
        writer = StringIO.new
        allow($stdout).to receive(:reopen)
        allow($stderr).to receive(:reopen)
        allow(store).to receive(:exit!)

        loaded = File.join(root, "lib", "lazy.rb")
        $LOADED_FEATURES.push(loaded)
        begin
          store.send(:record, writer, [])
        ensure
          $LOADED_FEATURES.delete(loaded)
        end

        expect(captured[:loaded_files]).to include(loaded)
      end
    end
  end

  it "writes a map after a green suite and does not lose the adapter return" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({}, root: root)
      integration = instance_double(Saboteur::Integration::RSpec, run_all: true,
                                                                  test_files: ["/root/spec/a_spec.rb"])
      recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
      map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
      allow(recorder).to receive(:result).and_return(map)
      # The recorder must also watch the suite's own files: a spec can read
      # a constant directly, and those hits map the mutant to its test (#319).
      # Captured, then asserted after record returns: an expect inside the
      # block fails under record's rescue, whose exit! would kill the whole
      # spec process and turn a clean mutant kill into a report-less error.
      recorded = nil
      allow(Saboteur::Selection::Recorder).to receive(:new) do |files|
        recorded = files
        recorder
      end
      store = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                  supervisor: nil, diagnostics: nil)
      writer = StringIO.new
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      # Stub exit! like the validation spec above: a mutant that leaves
      # recorder nil raises inside record's rescue, and a real exit! would
      # kill the spec process and report a RuntimeError instead of a kill.
      allow(store).to receive(:exit!)
      store.send(:record, writer, ["/root/lib/a.rb"])
      expect(recorded).to eq(["/root/lib/a.rb", "/root/spec/a_spec.rb"])
      expect(JSON.parse(writer.string)["tests"]).to eq(["t1"])
    end
  end
end
