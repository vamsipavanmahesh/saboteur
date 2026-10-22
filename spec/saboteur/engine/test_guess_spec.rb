# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe Saboteur::Engine::TestGuess do
  let(:base_source) { "class Widget\n  def thing\n    1\n  end\nend\n" }
  let(:changed_source) { "class Widget\n  def thing\n    2\n  end\nend\n" }
  let(:dir) { File.realpath(Dir.mktmpdir("saboteur-guess")) }

  after { FileUtils.remove_entry(dir) }

  def git(*args)
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
  end

  def write(path, text = "# x\n")
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  def guess(include: ["lib/**/*.rb", "app/**/*.rb", "src/**/*.rb"])
    config = Saboteur::Config.new({ "since" => "HEAD", "include" => include }, root: dir)
    described_class.new(config).call
  end

  before do
    git("init", "-q")
    # Background gc/maintenance races the teardown's remove_entry (its lock
    # file can vanish mid-delete on macOS).
    git("config", "gc.auto", "0")
    git("config", "maintenance.auto", "false")
    %w[lib/a.rb lib/deep/b.rb lib/c.rb app/models/d.rb lib/e.rb].each { |file| write(file, base_source) }
    %w[spec/a_spec.rb spec/deep/b_spec.rb spec/models/d_spec.rb spec/lib/e_spec.rb spec/stray_spec.rb].each do |f|
      write(f)
    end
    git("add", ".")
    git("commit", "-q", "-m", "base")
  end

  it "flattens three segments without retaining the unchanged namespace path" do
    config = Saboteur::Config.new({}, root: dir)
    guesser = described_class.new(config)
    expect(guesser.send(:flattened_below_namespace, ["rack/test/methods"]))
      .to eq(["rack/methods"])
  end

  it "calls a spec that vanished before it was read not a regular file" do
    guesser = described_class.new(Saboteur::Config.new({}, root: dir))
    expect(guesser.send(:unrunnable_reason, "spec/vanished_spec.rb")).to eq("not a regular file")
  end

  # A Minitest project has no spec/ directory (or no *_spec.rb in it), so a
  # full run matches every source file to nothing: the stop must be one line
  # naming the real problem (#606, sibling of the missing-rspec-core refusal
  # #542), not one line per file.
  describe "the no-RSpec-suite stop (#606)" do
    def full_guess
      config = Saboteur::Config.new({ "include" => ["lib/**/*.rb"] }, root: dir)
      described_class.new(config).call
    end

    before { FileUtils.remove_entry(File.join(dir, "spec")) }

    it "stops with one line pointing at Minitest when test/ exists but spec/ does not" do
      write("test/widget_test.rb")
      message = full_guess.unmatched_message
      expected = "no RSpec suite found - saboteur needs RSpec; " \
                 "this project appears to use Minitest (test/), see docs/minitest.md"
      expect(message).to eq(expected)
    end

    it "names no framework when neither spec/ nor test/ exists" do
      message = full_guess.unmatched_message
      expect(message).to include("no RSpec suite found - saboteur needs RSpec")
      expect(message).not_to include("Minitest")
    end

    it "treats a spec/ directory without *_spec.rb files as no suite" do
      write("test/widget_test.rb")
      write("spec/README.md")
      expect(full_guess.unmatched_message).to include("appears to use Minitest (test/)")
    end

    it "keeps the per-file expected-spec list behind --verbose" do
      write("test/widget_test.rb")
      result = full_guess
      verbose = result.unmatched_message(verbose: true)
      expect(verbose).to include("no RSpec suite found - saboteur needs RSpec",
                                 "lib/a.rb (expected spec/a_spec.rb)")
      expect(result.unmatched_message).not_to include("lib/a.rb")
    end

    it "keeps the per-file stop for a project that has an RSpec suite" do
      write("spec/a_spec.rb")
      message = full_guess.unmatched_message
      expect(message).to include("no spec found for")
      expect(message).not_to include("no RSpec suite found")
    end

    it "never claims a missing suite for a --subject run, which names its own expected spec" do
      config = Saboteur::Config.new({ "include" => ["lib/**/*.rb"] }, root: dir)
      message = described_class.new(config).call_for(["lib/a.rb"]).unmatched_message
      expect(message).to include("no spec found for")
      expect(message).not_to include("no RSpec suite found")
    end

    it "counts a suite that exists only in a nested spec directory" do
      write("spec/deep/b_spec.rb")
      message = full_guess.unmatched_message
      expect(message).to include("no spec found for")
      expect(message).not_to include("no RSpec suite found")
    end

    it "treats a spec/ directory holding only nested support files as no suite" do
      write("spec/support/helper.rb")
      expect(full_guess.unmatched_message).to include("no RSpec suite found")
    end

    it "stays silent when nothing is unmatched, even with no suite on disk" do
      expect(Saboteur::Engine::NoSuiteStop.layout(dir, [], false)).to be_nil
    end

    it "formats the verbose no-suite line with the exact per-file list" do
      write("test/widget_test.rb")
      result = full_guess
      pairs = result.unmatched.map { |file| result.send(:pair_description, file) }.join(", ")
      expected = "#{Saboteur::Engine::NoSuiteStop::MINITEST} Files without a guessed spec: #{pairs}."
      expect(result.unmatched_message(verbose: true)).to eq(expected)
    end

    # rspec_args can point RSpec outside spec/ (["--default-path", "specs"]):
    # claiming "no spec file exists" there is false and drops the
    # --test/--all remedy for a suite that would run (#606 QA).
    it "does not claim a missing suite when the suite lives outside spec/" do
      write("specs/a_spec.rb")
      message = full_guess.unmatched_message
      expect(message).to include("no spec found for")
      expect(message).not_to include("no RSpec suite found")
    end
  end

  it "warns through its diagnostics when untracked files cannot be opened race-free" do
    write("lib/new.rb", base_source)
    diagnostics = instance_double(Saboteur::Engine::Diagnostics)
    allow(diagnostics).to receive(:warn)
    allow(File).to receive(:const_defined?).and_call_original
    allow(File).to receive(:const_defined?).with(:NOFOLLOW).and_return(false)
    config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: dir)
    described_class.new(config, diagnostics: diagnostics).call

    expect(diagnostics).to have_received(:warn).with(/untracked/)
  end

  # A dashed gem name keeps dashes under lib/ but its specs live under the
  # underscored require name: gem acts-as-taggable-on tests
  # lib/acts-as-taggable-on/tagger.rb in spec/acts_as_taggable_on/ (#383).
  it "finds the underscored spec for a dashed gem directory" do
    write("lib/acts-as-taggable-on/tagger.rb", changed_source)
    write("spec/acts_as_taggable_on/tagger_spec.rb")
    result = guess
    expect(result.specs).to eq(["spec/acts_as_taggable_on/tagger_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  it "finds the underscored spec for a dashed file name" do
    write("lib/acts-as-taggable-on/taggable-proxy.rb", changed_source)
    write("spec/acts_as_taggable_on/taggable_proxy_spec.rb")
    result = guess
    expect(result.specs).to eq(["spec/acts_as_taggable_on/taggable_proxy_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  it "finds the underscored spec under spec/lib for a dashed gem directory" do
    write("lib/acts-as-taggable-on/tagger.rb", changed_source)
    write("spec/lib/acts_as_taggable_on/tagger_spec.rb")
    result = guess
    expect(result.specs).to eq(["spec/lib/acts_as_taggable_on/tagger_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # Both committed, so the changed-spec pickup cannot mask which one the
  # guess itself names.
  it "prefers the literal dashed spec when both exist" do
    write("lib/acts-as-taggable-on/tagger.rb", base_source)
    write("spec/acts-as-taggable-on/tagger_spec.rb")
    write("spec/acts_as_taggable_on/tagger_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "both specs")
    write("lib/acts-as-taggable-on/tagger.rb", changed_source)
    result = guess
    expect(result.specs).to eq(["spec/acts-as-taggable-on/tagger_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  it "finds the spec named after each changed source file" do
    %w[lib/a.rb lib/deep/b.rb app/models/d.rb lib/e.rb].each { |file| write(file, changed_source) }
    result = guess
    expect(result.specs).to eq(%w[spec/a_spec.rb spec/deep/b_spec.rb spec/lib/e_spec.rb spec/models/d_spec.rb])
    expect([result.unmatched, result.changed]).to eq([[], 4])
  end

  it "requires a spec for a file whose changed lines touch a constant literal (#306)" do
    write("lib/rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    git("add", ".")
    git("commit", "-q", "-m", "rules")
    write("lib/rules.rb", "RULES = {\n  a: 1,\n  b: 2\n}.freeze\n")

    result = guess
    expect(result.unmatched).to eq(["lib/rules.rb"])
  end

  # Verbatim, so the escape-hatch hint cannot be edited away silently (#640
  # review): a file no map entry covers hears the map remedy in the stop.
  # Two uncovered files, so the join separators in the pairs list and the
  # map hint are pinned too (#640 review): one file never exercises them.
  # The changed-specs segment gets its own verbatim pin, with two changed
  # specs so its join separator is pinned too (#640 review).
  it "prints the stop verbatim when the diff also changes specs (#640)" do
    write("spec/a_spec.rb", "# a2\n")
    write("spec/deep/b_spec.rb", "# b2\n")
    write("lib/c.rb", changed_source)

    expect(guess.unmatched_message).to eq(
      "no spec found for lib/c.rb (expected spec/c_spec.rb), so nothing ran. " \
      "Specs the diff adds or changes: spec/a_spec.rb, spec/deep/b_spec.rb. " \
      "Re-run the same command with one --test per existing spec path, or append --all to use " \
      "the whole suite without changing the source scope. If the layout defeats the naming " \
      "convention, map lib/c.rb by hand in config/saboteur_custom_map.rb (no entry covers it yet)."
    )
  end

  it "prints the two-file stop verbatim, separators included (#640)" do
    write("lib/rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    git("add", ".")
    git("commit", "-q", "-m", "rules")
    write("lib/rules.rb", "RULES = {\n  a: 1,\n  b: 2\n}.freeze\n")
    write("lib/c.rb", changed_source)

    expect(guess.unmatched_message).to eq(
      "no spec found for lib/c.rb (expected spec/c_spec.rb), lib/rules.rb (expected spec/rules_spec.rb), " \
      "so nothing ran. Re-run the same command with one --test per existing spec path, or append --all " \
      "to use the whole suite without changing the source scope. If the layout defeats the naming " \
      "convention, map lib/c.rb, lib/rules.rb by hand in config/saboteur_custom_map.rb (no entry covers it yet)."
    )
  end

  it "prints the full stop verbatim, escape-hatch hint included, for a file no map entry covers (#640)" do
    write("lib/c.rb", changed_source)

    expect(guess.unmatched_message).to eq(
      "no spec found for lib/c.rb (expected spec/c_spec.rb), so nothing ran. " \
      "Re-run the same command with one --test per existing spec path, or append --all to use " \
      "the whole suite without changing the source scope. If the layout defeats the naming " \
      "convention, map lib/c.rb by hand in config/saboteur_custom_map.rb (no entry covers it yet)."
    )
  end

  it "names the changed files that have no spec" do
    write("lib/a.rb", changed_source)
    write("lib/c.rb", changed_source)
    result = guess
    expect([result.specs, result.unmatched, result.changed]).to eq([["spec/a_spec.rb"], ["lib/c.rb"], 2])
  end

  # The custom map exists for layouts the naming convention cannot guess:
  # its entry wins, and the file stops being unmatched (#369).
  it "uses the custom map's specs for a file the convention cannot match (#369)" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/c.rb\" => [\"spec/unit/c_spec.rb\"]\n}.freeze\n")
    write("spec/unit/c_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/c.rb", changed_source)

    result = guess
    expect(result.specs).to eq(["spec/unit/c_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # Map paths are project-relative, never cwd-relative (#640 review): an
  # entry that leaves and re-enters the project still loads from a foreign
  # cwd, where a cwd-anchored load would misread it as escaping the root.
  it "anchors the custom map at the project root, not the cwd (#640)" do
    reentering = "../#{File.basename(dir)}/spec/unit/c_spec.rb"
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/c.rb\" => [\"#{reentering}\"]\n}.freeze\n")
    write("spec/unit/c_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/c.rb", changed_source)

    Dir.mktmpdir do |elsewhere|
      Dir.chdir(elsewhere) do
        result = guess
        expect(result.specs).to eq([reentering])
        expect(result.unmatched).to eq([])
      end
    end
  end

  # A mapped literal whose bytes are not valid UTF-8 reaches the glob
  # guard itself: match? raises ArgumentError, not the no-match ConfigError
  # a forced Dir.glob branch would produce (#480 audit).
  it "raises ArgumentError, not ConfigError, for a mapped spec literal with invalid UTF-8 bytes" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/c.rb\" => [\"spec/bad\\xFFx_spec.rb\"]\n}.freeze\n")
    # The mapped file exists (filesystems allow raw bytes), so the literal
    # survives expansion and reaches the glob guard itself.
    begin
      write("spec/bad\xFFx_spec.rb".b)
    rescue Errno::EILSEQ, Errno::EINVAL
      skip "this platform rejects filenames that are not valid UTF-8"
    end
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/c.rb", changed_source)

    expect { guess }.to raise_error(ArgumentError, /invalid byte sequence/)
  end

  it "prefers the custom map over the conventional spec path" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/a.rb\" => [\"spec/unit/a_spec.rb\"]\n}.freeze\n")
    write("spec/unit/a_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/a.rb", changed_source)

    result = guess
    expect(result.specs).to eq(["spec/unit/a_spec.rb"])
  end

  # A stale or mistyped entry must not shadow the way out: it warns,
  # then the naming convention and the usual stop guidance take over
  # (#640).
  it "warns and guesses by convention when a map entry's specs match no file (#640)" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/c.rb\" => [\"spec/unit/c_spec.rb\"]\n}.freeze\n")
    write("spec/c_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "map and conventional spec")
    write("lib/c.rb", changed_source)
    diagnostics = instance_double(Saboteur::Engine::Diagnostics)
    allow(diagnostics).to receive(:warn)
    config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: dir)
    result = described_class.new(config, diagnostics: diagnostics).call
    expect(result.specs).to eq(["spec/c_spec.rb"])
    expect(diagnostics).to have_received(:warn).with(/match no file/)
  end

  # With no conventional spec either, the run stops with the normal
  # unmatched guidance - not the bare ConfigError the entry used to die
  # with - and it does not point the file back at the map that already
  # failed it.
  it "falls through to the normal stop when neither the entry nor a conventional spec exists (#640)" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/c.rb\" => [\"spec/unit/c_spec.rb\"]\n}.freeze\n")
    git("add", ".")
    git("commit", "-q", "-m", "broken map")
    write("lib/c.rb", changed_source)
    result = guess
    expect(result.unmatched).to eq(["lib/c.rb"])
    expect(result.unmatched_message).to include("no spec found for lib/c.rb")
    expect(result.unmatched_message).not_to include("no entry covers it")
  end

  # The map is the documented escape hatch for layouts the convention
  # cannot guess: the stop names it for a file no entry covers.
  it "names the custom map in the stop when no entry covers the file (#640)" do
    write("lib/gizmo.rb", changed_source)
    result = guess
    expect(result.unmatched).to eq(["lib/gizmo.rb"])
    expect(result.unmatched_message).to include("config/saboteur_custom_map.rb (no entry covers it yet).")
  end

  it "maps one file to several specs" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/c.rb\" => " \
          "[\"spec/unit/c_spec.rb\", \"spec/unit/c_extra_spec.rb\"]\n}.freeze\n")
    write("spec/unit/c_spec.rb")
    write("spec/unit/c_extra_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/c.rb", changed_source)

    result = guess
    expect(result.specs).to eq(%w[spec/unit/c_extra_spec.rb spec/unit/c_spec.rb])
  end

  # An empty entry marks the file intentionally untested: it needs no
  # guessed spec, so it is not unmatched and no spec runs for it - and the
  # run says why instead of reading the empty list as "run everything".
  it "treats an empty custom-map entry as intentionally untested" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/c.rb\" => []\n}.freeze\n")
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/c.rb", changed_source)

    result = guess
    expect(result.unmatched).to eq([])
    expect(result.specs).to eq([])
    expect(result.excluded).to eq(["lib/c.rb"])
    expect(result.excluded_message).to eq("inferred specs: no spec is required for lib/c.rb: " \
                                          "intentionally untested in config/saboteur_custom_map.rb")
  end

  # Every excluded file is named, sorted, wherever the map lists them; an
  # excluded file contributes no spec and is not unmatched.
  it "collects every map-excluded file sorted" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/z.rb\" => [],\n  \"lib/a.rb\" => []\n}.freeze\n")
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/z.rb", changed_source)
    write("lib/a.rb", changed_source)
    write("lib/e.rb", changed_source)

    result = guess
    expect(result.excluded).to eq(%w[lib/a.rb lib/z.rb])
    expect(result.specs).to eq(["spec/lib/e_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # An injected map wins over the one on disk: the engine shares one load
  # with guessing, so guessing must not quietly reload (#369 review).
  it "uses the injected custom map instead of loading from disk" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/c.rb\" => []\n}.freeze\n")
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/c.rb", changed_source)

    config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: dir)
    result = described_class.new(config, custom_map: Saboteur::CustomMap.new([])).call
    expect(result.excluded).to eq([])
    expect(result.unmatched).to eq(["lib/c.rb"])
  end

  # Glob expansion keeps regular files only: a matched directory can never
  # run, and two patterns expanding to one spec run it once.
  it "drops directory matches and duplicate expansions from mapped globs" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/c.rb\" => [\"spec/unit/*\", \"spec/unit/c_*.rb\"]\n}.freeze\n")
    write("spec/unit/c_spec.rb")
    FileUtils.mkdir_p(File.join(dir, "spec/unit/nested_dir"))
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/c.rb", changed_source)

    expect(guess.specs).to eq(["spec/unit/c_spec.rb"])
  end

  # Glob spec values are expanded against the root: the literal glob string
  # must never reach RSpec (#369 review).
  it "expands glob spec values from the custom map" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"lib/c.rb\" => [\"spec/unit/**/*_spec.rb\"]\n}.freeze\n")
    write("spec/unit/c_spec.rb")
    write("spec/unit/deep/c_extra_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/c.rb", changed_source)

    expect(guess.specs).to eq(["spec/unit/c_spec.rb", "spec/unit/deep/c_extra_spec.rb"])
  end

  # Every vanished spec is named, in order, comma-separated, and the run
  # then falls through instead of dying on the entry (#640).
  it "names each vanished spec in the warning" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  %r{\\Alib/extra/(.*)\\.rb\\z} => " \
          "['spec/extra/\\1_spec.rb', 'spec/other/\\1_spec.rb']\n}.freeze\n")
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/extra/widget.rb", changed_source)
    diagnostics = instance_double(Saboteur::Engine::Diagnostics)
    allow(diagnostics).to receive(:warn)
    config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: dir)
    result = described_class.new(config, diagnostics: diagnostics).call

    expect(diagnostics).to have_received(:warn).with(
      "fix the custom map entry for lib/extra/widget.rb: spec(s) " \
      "spec/extra/widget_spec.rb, spec/other/widget_spec.rb match no file"
    )
    expect(result.unmatched).to eq(["lib/extra/widget.rb"])
  end

  # A regexp backreference can fill in a spec that does not exist: the
  # entry is stale or mistyped, so it warns and the naming convention and
  # the usual stop guidance take over (#640; the entry stopped the run
  # with a ConfigError under #369).
  it "warns and falls through when a mapped regexp spec expands to a missing file" do
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  %r{\\Alib/extra/(.*)\\.rb\\z} => ['spec/wrong/\\1_spec.rb']\n}.freeze\n")
    write("spec/extra/widget_spec.rb")
    write("lib/extra/widget.rb", base_source)
    git("add", ".")
    git("commit", "-q", "-m", "map and conventional spec")
    write("lib/extra/widget.rb", changed_source)
    diagnostics = instance_double(Saboteur::Engine::Diagnostics)
    allow(diagnostics).to receive(:warn)
    config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: dir)
    result = described_class.new(config, diagnostics: diagnostics).call

    expect(result.specs).to eq(["spec/extra/widget_spec.rb"])
    expect(diagnostics).to have_received(:warn).with(
      "fix the custom map entry for lib/extra/widget.rb: spec(s) spec/wrong/widget_spec.rb match no file"
    )
  end

  # Message style (#332): a long list is cut to the first five names and a
  # count of the rest, so the warning stays scannable.
  it "names at most five stale specs and counts the rest" do
    entries = (1..7).map { |n| "spec/wrong/widget_#{n}_spec.rb" }
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = { \"lib/extra/widget.rb\" => #{entries.inspect} }.freeze\n")
    write("lib/extra/widget.rb", base_source)
    git("add", ".")
    git("commit", "-q", "-m", "map")
    write("lib/extra/widget.rb", changed_source)
    diagnostics = instance_double(Saboteur::Engine::Diagnostics)
    allow(diagnostics).to receive(:warn)
    config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: dir)
    described_class.new(config, diagnostics: diagnostics).call

    expect(diagnostics).to have_received(:warn).with(
      "fix the custom map entry for lib/extra/widget.rb: spec(s) " \
      "spec/wrong/widget_1_spec.rb, spec/wrong/widget_2_spec.rb, spec/wrong/widget_3_spec.rb, " \
      "spec/wrong/widget_4_spec.rb, spec/wrong/widget_5_spec.rb, and 2 more match no file"
    )
  end

  # The cap's boundary (#799 dogfood): five names exactly is not cut, six
  # counts one more, and the count is names minus five.
  [
    [5, "spec/wrong/widget_1_spec.rb, spec/wrong/widget_2_spec.rb, spec/wrong/widget_3_spec.rb, " \
        "spec/wrong/widget_4_spec.rb, spec/wrong/widget_5_spec.rb"],
    [6, "spec/wrong/widget_1_spec.rb, spec/wrong/widget_2_spec.rb, spec/wrong/widget_3_spec.rb, " \
        "spec/wrong/widget_4_spec.rb, spec/wrong/widget_5_spec.rb, and 1 more"],
    [8, "spec/wrong/widget_1_spec.rb, spec/wrong/widget_2_spec.rb, spec/wrong/widget_3_spec.rb, " \
        "spec/wrong/widget_4_spec.rb, spec/wrong/widget_5_spec.rb, and 3 more"]
  ].each do |count, list|
    it "shows #{count} stale specs as \"#{list}\"" do
      entries = (1..count).map { |n| "spec/wrong/widget_#{n}_spec.rb" }
      write("config/saboteur_custom_map.rb",
            "SABOTEUR_CUSTOM_MAP = { \"lib/extra/widget.rb\" => #{entries.inspect} }.freeze\n")
      write("lib/extra/widget.rb", base_source)
      git("add", ".")
      git("commit", "-q", "-m", "map")
      write("lib/extra/widget.rb", changed_source)
      diagnostics = instance_double(Saboteur::Engine::Diagnostics)
      allow(diagnostics).to receive(:warn)
      config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: dir)
      described_class.new(config, diagnostics: diagnostics).call

      expect(diagnostics).to have_received(:warn).with(
        "fix the custom map entry for lib/extra/widget.rb: spec(s) #{list} match no file"
      )
    end
  end

  # A changed spec is not a changed source file: it needs no spec of its
  # own. It still runs, as a spec changed in the diff (#307).
  it "ignores changed files that saboteur would not mutate" do
    write("lib/a.rb", changed_source)
    write("spec/stray_spec.rb", "# changed\n")
    result = guess
    expect([result.specs, result.unmatched, result.changed]).to eq([%w[spec/a_spec.rb spec/stray_spec.rb], [], 1])
  end

  it "only drops the lib or app directory when guessing, not any first directory" do
    write("src/f.rb", base_source)
    write("spec/f_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "more")
    write("src/f.rb", changed_source)
    expect(guess.unmatched).to eq(["src/f.rb"])
  end

  it "does not treat a root file named lib as a source directory" do
    write("lib.rb", base_source)
    write("spec/lib/lib_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "root file")
    write("lib.rb", changed_source)
    expect(guess(include: ["lib.rb"]).unmatched).to eq(["lib.rb"])
  end

  context "with Rails request specs" do
    before do
      write("app/controllers/users_controller.rb", base_source)
      write("app/controllers/api/orders_controller.rb", base_source)
      write("app/controllers/api/items_controller.rb", base_source)
      write("spec/requests/users_spec.rb")
      write("spec/requests/api/orders_controller_spec.rb")
      write("spec/requests/api/items_spec.rb")
      write("spec/requests/api/items_controller_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "controllers")
    end

    it "maps a controller to its request spec with or without the controller suffix" do
      %w[users api/orders api/items].each { |name| write("app/controllers/#{name}_controller.rb", changed_source) }
      result = guess
      expect(result.specs).to eq(%w[spec/requests/api/items_controller_spec.rb
                                    spec/requests/api/orders_controller_spec.rb spec/requests/users_spec.rb])
      expect(result.unmatched).to eq([])
    end

    it "prefers a controller spec over a request spec" do
      write("spec/controllers/users_controller_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "ctrl spec")
      write("app/controllers/users_controller.rb", changed_source)
      expect(guess.specs).to eq(["spec/controllers/users_controller_spec.rb"])
    end
  end

  context "with packwerk packs" do
    before do
      write("packs/billing/package.yml", "enforce_dependencies: true\n")
      write("packs/billing/app/models/invoice.rb", base_source)
      write("packs/billing/app/controllers/invoices_controller.rb", base_source)
      write("packs/billing/lib/tax.rb", base_source)
      write("packs/billing/app/models/orphan.rb", base_source)
      write("packs/billing/spec/models/invoice_spec.rb")
      write("packs/billing/spec/requests/invoices_spec.rb")
      write("packs/billing/spec/tax_spec.rb")
      write("spec/models/orphan_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "packs")
    end

    it "maps a pack file to the spec inside the same pack" do
      %w[app/models/invoice app/controllers/invoices_controller lib/tax].each do |name|
        write("packs/billing/#{name}.rb", changed_source)
      end
      result = guess(include: ["packs/**/*.rb"])
      expect(result.specs).to eq(%w[packs/billing/spec/models/invoice_spec.rb
                                    packs/billing/spec/requests/invoices_spec.rb
                                    packs/billing/spec/tax_spec.rb])
      expect(result.unmatched).to eq([])
    end

    it "does not borrow a spec from another pack or the root" do
      write("packs/billing/app/models/orphan.rb", changed_source)
      expect(guess(include: ["packs/**/*.rb"]).unmatched).to eq(["packs/billing/app/models/orphan.rb"])
    end

    it "uses the nearest pack when packs nest" do
      write("packs/billing/inner/package.yml", "enforce_dependencies: true\n")
      write("packs/billing/inner/lib/gem.rb", base_source)
      write("packs/billing/spec/gem_spec.rb")
      write("packs/billing/inner/spec/gem_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "nested pack")
      write("packs/billing/inner/lib/gem.rb", changed_source)
      expect(guess(include: ["packs/**/*.rb"]).specs).to eq(["packs/billing/inner/spec/gem_spec.rb"])
    end

    it "does not treat a package.yml at the root as a pack" do
      write("package.yml", "enforce_dependencies: true\n")
      write("lib/plain.rb", base_source)
      write("spec/plain_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "root package.yml")
      write("lib/plain.rb", changed_source)
      expect(guess.specs).to eq(["spec/plain_spec.rb"])
    end

    it "finds packs at any depth from package.yml, not a hardcoded packs directory" do
      write("components/ledger/package.yml")
      write("components/ledger/app/models/entry.rb", base_source)
      write("components/ledger/spec/models/entry_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "ledger")
      write("components/ledger/app/models/entry.rb", changed_source)
      expect(guess(include: ["components/**/*.rb"]).specs).to eq(["components/ledger/spec/models/entry_spec.rb"])
    end
  end

  it "lists candidates most specific first, with the lib variant before the full stem" do
    guesser = described_class.new(Saboteur::Config.new({}, root: dir))
    expect(guesser.send(:candidates_for, "app/models/user.rb"))
      .to eq(["spec/models/user_spec.rb", "spec/lib/models/user_spec.rb", "spec/app/models/user_spec.rb",
              "spec/unit/models/user_spec.rb", "spec/unit/lib/models/user_spec.rb",
              "spec/unit/app/models/user_spec.rb", "spec/lib/user_spec.rb", "spec/app/user_spec.rb",
              "spec/user_spec.rb", "spec/unit/user_spec.rb"])
    expect(guesser.send(:candidates_for, "lib/a/b.rb"))
      .to eq(["spec/a/b_spec.rb", "spec/lib/a/b_spec.rb", "spec/unit/a/b_spec.rb",
              "spec/unit/lib/a/b_spec.rb", "spec/lib/b_spec.rb", "spec/b_spec.rb", "spec/unit/b_spec.rb"])
  end

  it "adds request spec names only for controllers" do
    guesser = described_class.new(Saboteur::Config.new({}, root: dir))
    expect(guesser.send(:request_names, "models/user")).to eq([])
    expect(guesser.send(:request_names, "controllers/api/users_controller"))
      .to eq(["requests/api/users_controller", "requests/api/users"])
  end

  it "detects pack directories once per run" do
    guesser = described_class.new(Saboteur::Config.new({}, root: dir))
    expect(Dir).to receive(:glob).with("**/package.yml", base: dir).once.and_return([])
    2.times { guesser.send(:pack_dirs) }
  end

  it "does not require a spec for a file whose changed lines touch no method" do
    write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\nend\n\n# a tail note\n")
    git("add", ".")
    git("commit", "-q", "-m", "tail note")
    write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\nend\n\n# a better tail note\n")
    result = guess
    expect([result.specs, result.unmatched, result.subjectless, result.changed]).to eq([[], [], ["lib/c.rb"], 1])
  end

  it "does not require a spec for a deletion whose remaining context lines touch no method" do
    write("lib/c.rb", "# errors\n\nclass FooError < StandardError\nend\n\nclass BarError < StandardError\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "error classes")
    write("lib/c.rb", "# errors\n\nclass BarError < StandardError\nend\n")
    result = guess
    expect([result.unmatched, result.subjectless]).to eq([[], ["lib/c.rb"]])
  end

  # Issue #484: a deletion-only edit that keeps the enclosing method must not
  # hard-stop the pr preset. The neighbor lines around the deletion mark the
  # method as changed, but a file whose diff adds no new lines has no new code
  # to mutate - the diff itself is the change the suite covers.
  it "does not require a spec for a deletion-only edit that leaves the method's remaining lines mutable" do
    write("lib/plugin.rb", <<~RUBY)
      module Plugin
        def rules
          Helper.validate(1)
          Helper.call(1, 2)
        end

        def helper_body
          0
        end
      end
    RUBY
    git("add", ".")
    git("commit", "-q", "-m", "plugin")
    write("lib/plugin.rb", <<~RUBY)
      module Plugin
        def rules
          Helper.call(1, 2)
        end
      end
    RUBY
    result = guess
    expect([result.unmatched, result.subjectless]).to eq([[], ["lib/plugin.rb"]])
  end

  # Monorepo layout: the project root sits below the git toplevel, so git
  # diff paths carry the subdir prefix while the guess's line map is
  # project-root-relative. The exclusion must still fire (#484).
  it "treats a deletion-only file as subjectless when the project root sits below the git toplevel" do
    write("sub/lib/plugin.rb", <<~RUBY)
      module Plugin
        def rules
          Helper.validate(1)
          Helper.call(1, 2)
        end
      end
    RUBY
    git("add", ".")
    git("commit", "-q", "-m", "plugin")
    write("sub/lib/plugin.rb", <<~RUBY)
      module Plugin
        def rules
          Helper.call(1, 2)
        end
      end
    RUBY
    config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] },
                                  root: File.join(dir, "sub"))
    result = described_class.new(config).call
    expect([result.unmatched, result.subjectless]).to eq([[], ["lib/plugin.rb"]])
  end

  it "does not require a spec when the changed method differs only in comments" do
    write("lib/c.rb", "class Widget\n  def thing\n    # a note\n    1\n  end\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "note")
    write("lib/c.rb", "class Widget\n  def thing\n    # a better note\n    1\n  end\nend\n")
    expect(guess.subjectless).to eq(["lib/c.rb"])
  end

  it "still requires specs for the other files when one change touches no method" do
    write("lib/a.rb", changed_source)
    write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\nend\n\n# a tail note\n")
    result = guess
    expect([result.specs, result.unmatched, result.subjectless, result.changed])
      .to eq([["spec/a_spec.rb"], [], ["lib/c.rb"], 2])
  end

  it "does not guess a spec for a file with no changed mutation subjects" do
    write("spec/c_spec.rb")
    write("lib/c.rb", "class Widget\n  def thing\n    # a note\n    1\n  end\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "c with spec")
    write("lib/c.rb", "class Widget\n  def thing\n    # a better note\n    1\n  end\nend\n")
    result = guess
    expect([result.specs, result.unmatched, result.subjectless]).to eq([[], [], ["lib/c.rb"]])
  end

  it "checks whole-file change ranges by interval in the diff route, without enumerating them" do
    write("lib/c.rb", changed_source)
    lines = Class.new(Range) do
      def each(*) = raise("enumerated a huge range")

      def map(*) = raise("enumerated a huge range")

      def any?(*) = raise("enumerated a huge range")
    end.new(2, 3)
    allow(Saboteur::Selection::GitDiff).to receive(:changed_lines)
      .and_return({ File.join(dir, "lib/c.rb") => lines })
    allow(Saboteur::Selection::GitDiff).to receive(:merge_base).and_return("HEAD")
    allow(Saboteur::Selection::GitDiff).to receive(:file_at).and_return(base_source)
    result = guess
    expect([result.unmatched, result.subjectless]).to eq([["lib/c.rb"], []])
  end

  it "detects a subjectless whole-file range by interval, without enumerating it" do
    write("lib/c.rb", changed_source)
    lines = Class.new(Range) do
      def each(*) = raise("enumerated a huge range")

      def map(*) = raise("enumerated a huge range")

      def any?(*) = raise("enumerated a huge range")
    end.new(5, 5)
    allow(Saboteur::Selection::GitDiff).to receive(:changed_lines)
      .and_return({ File.join(dir, "lib/c.rb") => lines })
    allow(Saboteur::Selection::GitDiff).to receive(:merge_base).and_return("HEAD")
    allow(Saboteur::Selection::GitDiff).to receive(:file_at).and_return(base_source)
    expect(guess.subjectless).to eq(["lib/c.rb"])
  end

  it "falls back for a subjectful file without a spec when the other change is subjectless with a spec" do
    write("lib/a.rb", "class Widget\n  def thing\n    # a better note\n    1\n  end\nend\n")
    write("lib/c.rb", "class Widget\n  def thing\n    2\n  end\nend\n")
    result = guess
    expect([result.specs, result.unmatched, result.subjectless]).to eq([[], ["lib/c.rb"], ["lib/a.rb"]])
  end

  it "lists a spec guessed for two changed files once" do
    write("lib/deep/dup.rb", base_source)
    write("deep/dup.rb", base_source)
    write("spec/deep/dup_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "two files one spec")
    write("lib/deep/dup.rb", changed_source)
    write("deep/dup.rb", changed_source)
    result = guess(include: ["lib/**/*.rb", "deep/**/*.rb"])
    expect(result.specs).to eq(["spec/deep/dup_spec.rb"])
  end

  it "lists unmatched files sorted, however git ordered the diff" do
    write("lib/z.rb", base_source)
    git("add", ".")
    git("commit", "-q", "-m", "z")
    write("lib/c.rb", changed_source)
    write("lib/z.rb", changed_source)
    lines = { File.join(dir, "lib/z.rb") => Set[3], File.join(dir, "lib/c.rb") => Set[3] }
    allow(Saboteur::Selection::GitDiff).to receive(:changed_lines).and_return(lines)
    expect(guess.unmatched).to eq(["lib/c.rb", "lib/z.rb"])
  end

  it "is not subjectless when the changed lines span two subjects" do
    write("lib/c.rb", "class Widget\n  def thing\n    __LINE__\n  end\n\n  def other\n    __LINE__\n  end\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "two subjects")
    write("lib/c.rb",
          "class Widget\n  def thing\n    1 + __LINE__\n  end\n\n  def other\n    2 + __LINE__\n  end\nend\n")
    expect(guess.subjectless).to eq([])
  end

  it "stays subjectless when a comment added above a method shifts its __LINE__" do
    write("lib/c.rb", "class Widget\n  def thing\n    __LINE__\n  end\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "line marker")
    write("lib/c.rb", "# a note\nclass Widget\n  def thing\n    __LINE__\n  end\nend\n")
    result = guess
    expect([result.unmatched, result.subjectless]).to eq([[], ["lib/c.rb"]])
  end

  it "scopes the diff to the included files and reports through the run diagnostics" do
    write("lib/c.rb", changed_source)
    lines = { File.join(dir, "lib/c.rb") => Set[3] }
    allow(Saboteur::Selection::GitDiff).to receive(:changed_lines).and_return(lines)
    diagnostics = instance_double(Saboteur::Engine::Diagnostics, warn: nil, inform: nil)
    config = Saboteur::Config.new({ "since" => "HEAD" }, root: dir)
    described_class.new(config, diagnostics: diagnostics).call
    expect(Saboteur::Selection::GitDiff).to have_received(:changed_lines)
      .with("HEAD", root: dir, include: config.included_files.to_set, diagnostics: diagnostics)
  end

  # ruby-jwt consolidates claim specs: lib/jwt/claims/decode_verifier.rb is
  # covered by spec/jwt/claims_spec.rb, which the per-file guess never finds.
  # When the diff itself changes that consolidated spec and the spec reads a
  # constant the uncovered file defines, the file is covered and the pr
  # preset must not hard-stop (#538).
  it "treats a consolidated spec changed in the diff as covering the file it exercises (#538)" do
    verifier = "module JWT\n  module Claims\n    class DecodeVerifier\n      " \
               "def call\n        %d\n      end\n    end\n  end\nend\n"
    write("lib/jwt/claims/decode_verifier.rb", format(verifier, 1))
    write("spec/jwt/claims_spec.rb",
          "RSpec.describe JWT::Claims do\n  it \"verifies\" do\n    JWT::Claims::DecodeVerifier.new.call\n  end\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    write("lib/jwt/claims/decode_verifier.rb", format(verifier, 2))
    write("spec/jwt/claims_spec.rb",
          "RSpec.describe JWT::Claims do\n  it \"verifies\" do\n    " \
          "2.times { JWT::Claims::DecodeVerifier.new.call }\n  end\nend\n")
    result = guess
    expect(result.unmatched).to eq([])
    expect(result.referenced).to eq({})
    expect(result.specs).to include("spec/jwt/claims_spec.rb")
  end

  it "still stops for a mutable change no changed spec exercises (#538)" do
    verifier = "module JWT\n  module Claims\n    class DecodeVerifier\n      " \
               "def call\n        %d\n      end\n    end\n  end\nend\n"
    write("lib/jwt/claims/decode_verifier.rb", format(verifier, 1))
    write("spec/jwt/claims_spec.rb",
          "RSpec.describe JWT::Claims do\n  it \"verifies\" do\n    JWT.decode\n  end\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    write("lib/jwt/claims/decode_verifier.rb", format(verifier, 2))
    write("spec/jwt/claims_spec.rb",
          "RSpec.describe JWT::Claims do\n  it \"verifies\" do\n    JWT.decode\n    JWT.decode\n  end\nend\n")
    expect(guess.unmatched).to eq(["lib/jwt/claims/decode_verifier.rb"])
  end

  # The top-level literal is this file's coverage link to the changed
  # spec: drop it (the def's owner alone matches nothing) and the stop returns.
  it "treats a changed spec reading a constant literal as covering the file that assigns it (#538)" do
    write("lib/rules.rb", "RULES = [1]\nclass Rules\n  def use\n    RULES.sum\n  end\nend\n")
    write("spec/shop_spec.rb", "RSpec.describe \"rules\" do\n  it { RULES }\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    write("lib/rules.rb", "RULES = [2]\nclass Rules\n  def use\n    RULES.sum\n  end\nend\n")
    write("spec/shop_spec.rb", "RSpec.describe \"rules\" do\n  it { RULES }\n  it { RULES }\nend\n")
    result = guess
    expect(result.unmatched).to eq([])
    expect(result.referenced).to eq({})
    expect(result.specs).to include("spec/shop_spec.rb")
  end

  it "covers a top-level constant read inside a nested spec scope (#538)" do
    write("lib/rules.rb", "RULES = [1]\nclass Rules\n  def use\n    RULES.sum\n  end\nend\n")
    spec = "module Shop\n  RSpec.describe \"rules\" do\n    it { RULES }\n%s  end\nend\n"
    write("spec/shop_spec.rb", format(spec, ""))
    git("add", ".")
    git("commit", "-q", "-m", "base")
    write("lib/rules.rb", "RULES = [2]\nclass Rules\n  def use\n    RULES.sum\n  end\nend\n")
    write("spec/shop_spec.rb", format(spec, "    it { RULES }\n"))
    result = guess
    expect(result.unmatched).to eq([])
    expect(result.specs).to include("spec/shop_spec.rb")
  end

  it "treats a changed spec reading the constant bare under its owner scope as covering (#538)" do
    verifier = "module JWT\n  module Claims\n    class DecodeVerifier\n      " \
               "def call\n        %d\n      end\n    end\n  end\nend\n"
    write("lib/jwt/claims/decode_verifier.rb", format(verifier, 1))
    write("spec/jwt/claims_spec.rb",
          "module JWT\n  module Claims\n    RSpec.describe DecodeVerifier do\n      " \
          "it { DecodeVerifier.new.call }\n    end\n  end\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    write("lib/jwt/claims/decode_verifier.rb", format(verifier, 2))
    write("spec/jwt/claims_spec.rb",
          "module JWT\n  module Claims\n    RSpec.describe DecodeVerifier do\n      " \
          "it { DecodeVerifier.new.call }\n      it { DecodeVerifier.new.call }\n    end\n  end\nend\n")
    expect(guess.unmatched).to eq([])
  end

  it "still stops when the changed spec reads the constant bare outside its owner scope (#538)" do
    verifier = "module JWT\n  module Claims\n    class DecodeVerifier\n      " \
               "def call\n        %d\n      end\n    end\n  end\nend\n"
    write("lib/jwt/claims/decode_verifier.rb", format(verifier, 1))
    write("spec/other_spec.rb", "RSpec.describe \"other\" do\n  it { DecodeVerifier }\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    write("lib/jwt/claims/decode_verifier.rb", format(verifier, 2))
    write("spec/other_spec.rb", "RSpec.describe \"other\" do\n  it { DecodeVerifier }\n  it { DecodeVerifier }\nend\n")
    expect(guess.unmatched).to eq(["lib/jwt/claims/decode_verifier.rb"])
  end

  it "reports nothing changed" do
    expect(guess.changed).to eq(0)
  end

  it "names a changed source file the include scope hides (#483)" do
    write("engines/billing/lib/billing.rb", changed_source)
    write("docs/notes.md", "# notes\n")
    result = guess
    expect(result.changed).to eq(0)
    expect(result.out_of_scope).to eq(["engines/billing/lib/billing.rb"])
  end

  it "leaves out_of_scope empty when an included file changed" do
    write("lib/a.rb", changed_source)
    expect(guess.out_of_scope).to eq([])
  end

  it "reports no hidden source when an included file also changed alongside an excluded one (#483)" do
    write("lib/a.rb", changed_source)
    write("engines/billing/lib/billing.rb", changed_source)
    result = guess
    expect(result.changed).to eq(1)
    expect(result.out_of_scope).to eq([])
  end

  it "does not call an included file hidden when its change carries no lines (#483)" do
    FileUtils.chmod(0o755, File.join(dir, "lib/a.rb"))
    write("engines/billing/lib/billing.rb", changed_source)
    result = guess
    expect(result.changed).to eq(0)
    expect(result.out_of_scope).to eq(["engines/billing/lib/billing.rb"])
  end

  it "does not call a changed spec hidden source" do
    write("spec/stray_spec.rb", "# changed\n")
    result = guess
    expect(result.changed).to eq(0)
    expect(result.out_of_scope).to eq([])
  end

  it "maps each unmatched file to the conventional spec path for the retry hint" do
    write("lib/c.rb", changed_source)
    result = guess
    expect(result.hints).to eq("lib/c.rb" => "spec/c_spec.rb")
  end

  describe "specs changed in the diff (#307)" do
    it "adds a changed spec whose name does not map to the changed source file" do
      write("spec/requests/widgets_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "request spec")
      write("lib/a.rb", changed_source)
      write("spec/requests/widgets_spec.rb", "# changed\n")
      result = guess
      expect(result.specs).to eq(%w[spec/a_spec.rb spec/requests/widgets_spec.rb])
      expect(result.changed_specs).to eq(%w[spec/requests/widgets_spec.rb])
    end

    it "adds a spec the branch committed since the base" do
      git("branch", "-q", "base")
      write("lib/a.rb", changed_source)
      write("spec/requests/widgets_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "feature")
      config = Saboteur::Config.new({ "since" => "base", "include" => ["lib/**/*.rb"] }, root: dir)
      result = described_class.new(config).call
      expect(result.specs).to eq(%w[spec/a_spec.rb spec/requests/widgets_spec.rb])
    end

    it "adds an untracked new spec" do
      write("lib/a.rb", changed_source)
      write("spec/requests/new_spec.rb")
      expect(guess.specs).to eq(%w[spec/a_spec.rb spec/requests/new_spec.rb])
    end

    # A symlink can point anywhere, including another application's spec or
    # an excluded fixture; a dangling one cannot run at all.
    it "names a changed spec that is a symlink, dangling or not, instead of running it" do
      write("lib/a.rb", changed_source)
      File.symlink("missing_target.rb", File.join(dir, "spec/dangling_spec.rb"))
      File.symlink(File.join(dir, "spec/stray_spec.rb"), File.join(dir, "spec/linked_spec.rb"))
      result = guess
      expect(result.specs).to eq(%w[spec/a_spec.rb])
      expect(result.skipped_specs).to eq("spec/dangling_spec.rb" => "not a regular file",
                                         "spec/linked_spec.rb" => "not a regular file")
    end

    # RSpec applies --pattern and --exclude-pattern only to the directories
    # it scans, never to a file named as a test: the suite's own list decides.
    it "names a changed spec the configured suite excludes instead of running it" do
      write(".rspec", "--exclude-pattern spec/fixtures/**/*_spec.rb\n")
      git("add", ".")
      git("commit", "-q", "-m", "rspec options")
      write("lib/a.rb", changed_source)
      write("spec/fixtures/app/spec/wipe_spec.rb")
      write("spec/requests/widgets_spec.rb")
      result = guess
      expect(result.specs).to eq(%w[spec/a_spec.rb spec/requests/widgets_spec.rb])
      expect(result.skipped_specs.keys).to eq(%w[spec/fixtures/app/spec/wipe_spec.rb])
      expect(result.skipped_specs.values.first).to start_with("not loaded by the configured RSpec suite")
    end

    it "names a changed spec outside the suite's default path" do
      write("lib/a.rb", changed_source)
      write("test/widgets_spec.rb")
      result = guess
      expect(result.specs).to eq(%w[spec/a_spec.rb])
      expect(result.skipped_specs.keys).to eq(%w[test/widgets_spec.rb])
    end

    it "runs a changed file a custom suite pattern loads, whatever its name" do
      write("lib/a.rb", changed_source)
      write("spec/requests/widgets_feature.rb")
      config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"],
                                      "rspec_args" => ["--pattern", "spec/**/*_{spec,feature}.rb"] }, root: dir)
      expect(described_class.new(config).call.specs).to eq(%w[spec/a_spec.rb spec/requests/widgets_feature.rb])
    end

    # A renamed conventional spec leaves the source file unmatched: the
    # stop says the expected spec was deleted and names the specs to pass.
    it "says the expected spec was deleted and lists the changed specs when a file is unmatched" do
      write("lib/a.rb", changed_source)
      FileUtils.mkdir_p(File.join(dir, "spec/requests"))
      git("mv", "spec/a_spec.rb", "spec/requests/widgets_spec.rb")
      message = guess.unmatched_message
      expect(message).to include("lib/a.rb (expected spec/a_spec.rb, deleted in the diff)",
                                 "Specs the diff adds or changes: spec/requests/widgets_spec.rb.")
    end

    # Rails tests a controller as a request spec, the second candidate: its
    # deletion must be the one the stop names.
    it "names a deleted candidate that is not the first one as the expected spec" do
      write("app/controllers/users_controller.rb", "class UsersController\n  def a = 1\nend\n")
      write("spec/requests/users_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "controller")
      write("app/controllers/users_controller.rb", "class UsersController\n  def a = 2\nend\n")
      git("mv", "spec/requests/users_spec.rb", "spec/requests/accounts_spec.rb")
      message = guess.unmatched_message
      expect(message).to include("app/controllers/users_controller.rb " \
                                 "(expected spec/requests/users_spec.rb, deleted in the diff)",
                                 "Specs the diff adds or changes: spec/requests/accounts_spec.rb.")
    end

    # macOS git reports a precomposed (NFC) name while the directory entry,
    # and so the suite list, can be decomposed (NFD): one spec, two spellings.
    it "matches a changed spec to the suite list whatever Unicode form names it" do
      write("lib/a.rb", changed_source)
      write("spec/cafe\u0301_spec.rb")
      expect(guess.specs.map { |spec| spec.unicode_normalize(:nfc) })
        .to eq(["spec/a_spec.rb", "spec/caf\u00e9_spec.rb"])
      expect(guess.skipped_specs).to eq({})
    end

    # Only a deleted candidate replaces the first one in the stop: a
    # candidate skipped for another reason (a dangling symlink) does not.
    it "names the first candidate when the only skipped candidate was not deleted" do
      File.delete(File.join(dir, "spec/a_spec.rb"))
      git("add", ".")
      git("commit", "-q", "-m", "no spec")
      write("lib/a.rb", changed_source)
      FileUtils.mkdir_p(File.join(dir, "spec/lib"))
      File.symlink("missing_target.rb", File.join(dir, "spec/lib/a_spec.rb"))
      expect(guess.skipped_specs).to eq("spec/lib/a_spec.rb" => "not a regular file")
      expect(guess.unmatched_message).to include("lib/a.rb (expected spec/a_spec.rb)")
    end

    # A same-basename spec anywhere under spec/** is a near miss worth
    # naming in the stop, so the user can --test it without hunting (#370).
    it "names same-basename specs found under spec/** when the run stops" do
      FileUtils.mkdir_p(File.join(dir, "spec/models"))
      write("lib/x.rb", changed_source)
      write("spec/models/x_spec.rb")
      expect(guess.unmatched_message).to include("lib/x.rb (expected spec/x_spec.rb; found: spec/models/x_spec.rb)")
    end

    # #712: pin the "; found: " prefix and the ", " join verbatim with a
    # two-file example.
    it "joins two same-basename finds with the separator verbatim (#712)" do
      FileUtils.mkdir_p(File.join(dir, "spec/models"))
      write("lib/x.rb", changed_source)
      write("spec/a/x_spec.rb")
      write("spec/models/x_spec.rb")
      expect(guess.unmatched_message)
        .to include("lib/x.rb (expected spec/x_spec.rb; found: spec/a/x_spec.rb, spec/models/x_spec.rb)")
    end

    # The near misses come sorted and bounded at three: more same-basename
    # specs than that are cut after the third in path order (#585 dogfood).
    it "names at most the first three same-basename specs, sorted" do
      write("lib/x.rb", changed_source)
      write("spec/a.b/x_spec.rb")
      write("spec/a/x_spec.rb")
      write("spec/models/x_spec.rb")
      write("spec/requests/x_spec.rb")
      expect(guess.unmatched_message).to include(
        "lib/x.rb (expected spec/x_spec.rb; found: spec/a.b/x_spec.rb, spec/a/x_spec.rb, spec/models/x_spec.rb)"
      )
      expect(guess.unmatched_message).not_to include("spec/models/x_spec.rb, spec/requests/x_spec.rb)")
    end

    # A changed spec that exists but cannot run (a dangling symlink) was
    # not deleted: the stop must not say it was.
    it "does not call an unrunnable expected spec deleted in the diff" do
      File.delete(File.join(dir, "spec/a_spec.rb"))
      File.symlink("missing_target.rb", File.join(dir, "spec/a_spec.rb"))
      write("lib/a.rb", changed_source)
      expect(guess.skipped_specs).to eq("spec/a_spec.rb" => "not a regular file")
      expect(guess.unmatched_message).to include("lib/a.rb (expected spec/a_spec.rb)")
      expect(guess.unmatched_message).not_to include("deleted in the diff")
    end

    it "adds no found clause when no same-basename spec exists" do
      write("lib/y.rb", changed_source)
      expect(guess.unmatched_message).to include("lib/y.rb (expected spec/y_spec.rb)")
      expect(guess.unmatched_message).not_to include("found:")
    end

    # Dir.glob orders path components, not whole strings: a/ comes before
    # a-b/ although "a-b/" sorts first as a string, so the sort is
    # observable (kills the chain_removal of .sort).
    it "names same-basename specs in string-sorted order, not glob order" do
      write("lib/x.rb", changed_source)
      write("spec/a/x_spec.rb")
      write("spec/a-b/x_spec.rb")
      expect(guess.unmatched_message).to include("; found: spec/a-b/x_spec.rb, spec/a/x_spec.rb)")
    end

    # The found list is capped at three so a stop message stays readable
    # (kills the chain_removal of .first(3)).
    it "caps the same-basename found list at three" do
      write("lib/x.rb", changed_source)
      %w[a b c d].each { |dir_name| write("spec/#{dir_name}/x_spec.rb") }
      expect(guess.unmatched_message)
        .to include("; found: spec/a/x_spec.rb, spec/b/x_spec.rb, spec/c/x_spec.rb)")
    end

    # A basename is data, not a pattern: glob metacharacters in it must
    # match literally, or the near miss is silently lost.
    it "matches a basename with glob metacharacters literally" do
      FileUtils.mkdir_p(File.join(dir, "spec/models"))
      write("lib/x[1].rb", changed_source)
      write("spec/models/x[1]_spec.rb")
      expect(guess.unmatched_message).to include("found: spec/models/x[1]_spec.rb")
    end

    # The same comparison on every platform: the suite lists the NFD
    # spelling while git reports the NFC one.
    it "finds a changed spec in a suite list that spells it in another Unicode form" do
      write("lib/a.rb", changed_source)
      write("spec/caf\u00e9_spec.rb")
      allow_any_instance_of(Saboteur::Integration::RSpec).to receive(:configured_spec_files)
        .and_return(["spec/a_spec.rb", "spec/cafe\u0301_spec.rb"])
      expect(guess.specs).to eq(["spec/a_spec.rb", "spec/caf\u00e9_spec.rb"])
    end

    # A spec name that is not valid UTF-8 compares by its bytes: it cannot
    # be normalized, and it must still be found in the suite list.
    it "runs a changed spec whose name is not valid UTF-8" do
      write("lib/a.rb", changed_source)
      name = "spec/raw_\xFF_spec.rb".b
      begin
        File.write(File.join(dir.b, name), "# x\n")
      rescue Errno::EILSEQ, Errno::EINVAL
        skip "this platform rejects filenames that are not valid UTF-8"
      end
      expect(guess.specs.map(&:b)).to eq(["spec/a_spec.rb".b, name])
    end

    # A non-ASCII root joined with a git path that holds high bytes must not
    # mix encodings; the LANG=C CI job runs this under a US-ASCII locale.
    it "joins a non-ASCII root with a non-ASCII spec path" do
      root = File.join(dir, "caf\u00e9")
      FileUtils.mkdir_p(File.join(root, "lib"))
      FileUtils.mkdir_p(File.join(root, "spec/requests"))
      File.write(File.join(root, "lib/w.rb"), base_source)
      File.write(File.join(root, "spec/w_spec.rb"), "# x\n")
      git("add", ".")
      git("commit", "-q", "-m", "app")
      File.write(File.join(root, "lib/w.rb"), changed_source)
      File.write(File.join(root, "spec/requests/\u00e9tat_spec.rb"), "# x\n")
      config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: root)
      result = described_class.new(config).call
      if Encoding.find("filesystem") == Encoding::UTF_8
        expect(result.specs).to eq(["spec/requests/\u00e9tat_spec.rb", "spec/w_spec.rb"])
      else
        # RSpec's own path expansion mixes encodings here; the changed spec
        # is named, not run, and nothing raises.
        expect(result.specs).to eq(["spec/w_spec.rb"])
        expect(result.skipped_specs.values).to eq(["the configured RSpec suite's files could not be listed " \
                                                   "(Encoding::CompatibilityError)"])
      end
    end

    # RSpec lists the suite once per run, not once per changed spec, and a
    # failed listing is not retried for each one.
    [[:list, nil], [:fail, Encoding::CompatibilityError]].each do |kind, error|
      it "asks RSpec for the suite's files once when the listing #{kind == :list ? 'succeeds' : 'fails'}" do
        write("lib/a.rb", changed_source)
        write("spec/requests/one_spec.rb")
        write("spec/requests/two_spec.rb")
        calls = 0
        allow_any_instance_of(Saboteur::Integration::RSpec).to receive(:configured_spec_files) do
          calls += 1
          raise error, "incompatible" if error

          %w[spec/requests/one_spec.rb spec/requests/two_spec.rb]
        end
        guess
        expect(calls).to eq(1)
      end
    end

    it "names only deleted spec files, not other deleted files" do
      write("lib/a.rb", changed_source)
      File.delete(File.join(dir, "spec/stray_spec.rb"))
      File.delete(File.join(dir, "lib/e.rb"))
      expect(guess.skipped_specs).to eq("spec/stray_spec.rb" => "deleted in the diff")
    end

    it "lists skipped spec files in path order, whatever the reason" do
      write(".rspec", "--exclude-pattern spec/fixtures/**/*_spec.rb\n")
      git("add", ".")
      git("commit", "-q", "-m", "rspec options")
      write("lib/a.rb", changed_source)
      write("spec/fixtures/a_spec.rb")
      File.delete(File.join(dir, "spec/stray_spec.rb"))
      File.delete(File.join(dir, "spec/deep/b_spec.rb"))
      expect(guess.skipped_specs.keys).to eq(%w[spec/deep/b_spec.rb spec/fixtures/a_spec.rb spec/stray_spec.rb])
    end

    it "names changed specs instead of running them when the suite's files cannot be listed" do
      write("lib/a.rb", changed_source)
      write("spec/requests/widgets_spec.rb")
      allow_any_instance_of(Saboteur::Integration::RSpec).to receive(:configured_spec_files)
        .and_raise(Encoding::CompatibilityError, "incompatible character encodings")
      result = guess
      expect(result.specs).to eq(%w[spec/a_spec.rb])
      expect(result.skipped_specs).to eq("spec/requests/widgets_spec.rb" =>
        "the configured RSpec suite's files could not be listed (Encoding::CompatibilityError)")
    end

    it "lists a spec both inferred and changed once, as an inferred spec" do
      write("lib/a.rb", changed_source)
      write("spec/a_spec.rb", "# changed\n")
      result = guess
      expect(result.specs).to eq(%w[spec/a_spec.rb])
      expect(result.changed_specs).to be_empty
    end

    # Inference runs the conventional spec as it did before #307; the diff
    # check must not also call it skipped while it runs.
    it "does not report a changed inferred spec as skipped, even one the suite's patterns leave out" do
      write(".rspec", "--exclude-pattern spec/a_spec.rb\n")
      git("add", ".")
      git("commit", "-q", "-m", "rspec options")
      write("lib/a.rb", changed_source)
      write("spec/a_spec.rb", "# changed\n")
      result = guess
      expect(result.specs).to eq(%w[spec/a_spec.rb])
      expect(result.skipped_specs).to be_empty
    end

    it "leaves unchanged unrelated specs and changed non-spec files out" do
      write("lib/a.rb", changed_source)
      write("spec/spec_helper.rb", "# changed\n")
      write("spec/support/widget_helper.rb", "# new\n")
      expect(guess.specs).to eq(%w[spec/a_spec.rb])
    end

    it "does not run a spec the diff deletes, and names it" do
      write("lib/a.rb", changed_source)
      File.delete(File.join(dir, "spec/stray_spec.rb"))
      result = guess
      expect(result.specs).to eq(%w[spec/a_spec.rb])
      expect(result.skipped_specs).to eq("spec/stray_spec.rb" => "deleted in the diff")
    end

    it "adds no changed spec when no changed file has a mutation subject" do
      write("spec/requests/widgets_spec.rb")
      result = guess
      expect(result.specs).to be_empty
      expect(result.changed_specs).to be_empty
    end

    it "keeps a source file with no conventional spec unmatched even when another spec changed" do
      write("lib/c.rb", changed_source)
      write("spec/requests/widgets_spec.rb")
      expect(guess.unmatched).to eq(%w[lib/c.rb])
    end

    # The root can be a subdirectory of the repository (a monorepo app):
    # a spec changed elsewhere in the repository is not one of its specs.
    it "takes changed specs only from inside the configured root, relative to it" do
      write("svc/lib/a.rb", base_source)
      write("svc/spec/a_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "svc")
      write("svc/lib/a.rb", changed_source)
      write("svc/spec/requests/widgets_spec.rb")
      write("other/spec/outside_spec.rb")
      config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] },
                                    root: File.join(dir, "svc"))
      expect(described_class.new(config).call.specs).to eq(%w[spec/a_spec.rb spec/requests/widgets_spec.rb])
    end

    it "adds changed specs to a --subject run inside the diff" do
      write("lib/a.rb", changed_source)
      write("spec/requests/widgets_spec.rb")
      config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: dir)
      result = described_class.new(config).call_for(["lib/a.rb"], ["Widget#thing"])
      expect(result.specs).to eq(%w[spec/a_spec.rb spec/requests/widgets_spec.rb])
    end
  end

  describe "call_for under --since (a --subject run stays inside the diff)" do
    it "keeps a file when any one of its subjects matches the pattern" do
      write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\n  def added\n    2\n  end\nend\n")
      write("spec/c_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "two subjects")
      write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\n  def added\n    3\n  end\nend\n")
      expect(guess_for(["lib/c.rb"], ["Widget#added"]).specs).to eq(["spec/c_spec.rb"])
    end

    it "keeps a file when its subject matches any one of the patterns" do
      write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\n  def added\n    2\n  end\nend\n")
      write("spec/c_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "two subjects")
      write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\n  def added\n    3\n  end\nend\n")
      expect(guess_for(["lib/c.rb"], ["Widget#added", "Widget#nope"]).specs).to eq(["spec/c_spec.rb"])
    end

    def guess_for(files, patterns)
      config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: dir)
      described_class.new(config).call_for(files, patterns)
    end

    it "drops a named subject whose file is unchanged, even when the file has no spec" do
      result = guess_for(["lib/c.rb"], ["Widget#thing"])
      expect([result.specs, result.unmatched, result.changed]).to eq([[], [], 0])
    end

    it "drops a named subject when only another method in its file changed" do
      write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\n  def added\n    2\n  end\nend\n")
      result = guess_for(["lib/c.rb"], ["Widget#thing"])
      expect([result.specs, result.unmatched, result.changed]).to eq([[], [], 0])
    end

    it "drops a named subject whose change is comment-only" do
      write("lib/c.rb", "class Widget\n  def thing\n    # a comment, not code\n    1\n  end\nend\n")
      result = guess_for(["lib/c.rb"], ["Widget#thing"])
      expect([result.specs, result.unmatched, result.changed]).to eq([[], [], 0])
    end

    it "infers the changed named subject's spec and skips an unchanged requested subject" do
      write("lib/a.rb", changed_source)
      result = guess_for(["lib/c.rb", "lib/a.rb"], ["Widget#thing"])
      expect([result.specs, result.unmatched, result.changed]).to eq([["spec/a_spec.rb"], [], 1])
    end

    it "drops a named subject that only shifted when lines were added above it" do
      write("lib/c.rb", "class Widget\n  def thing\n    __LINE__\n  end\nend\n")
      git("add", ".")
      git("commit", "-q", "-m", "line subject")
      write("lib/c.rb", "class Widget\n  def added\n    2\n  end\n\n  def thing\n    __LINE__\n  end\nend\n")
      result = guess_for(["lib/c.rb"], ["Widget#thing"])
      expect([result.specs, result.unmatched, result.changed]).to eq([[], [], 0])
    end

    it "still reports a changed named subject with no spec as unmatched" do
      write("lib/c.rb", changed_source)
      result = guess_for(["lib/c.rb"], ["Widget#thing"])
      expect([result.specs, result.unmatched, result.changed]).to eq([[], ["lib/c.rb"], 1])
    end
  end

  describe "without --since (every included file is in scope)" do
    def guess_all(include: ["lib/**/*.rb", "app/**/*.rb"])
      config = Saboteur::Config.new({ "include" => include }, root: dir)
      described_class.new(config).call
    end

    it "guesses a spec for every included file with a mutation subject" do
      result = guess_all
      expect(result.specs).to eq(%w[spec/a_spec.rb spec/deep/b_spec.rb spec/lib/e_spec.rb spec/models/d_spec.rb])
      expect(result.unmatched).to eq(["lib/c.rb"])
      expect(result.hints).to eq("lib/c.rb" => "spec/c_spec.rb")
      expect(result.changed).to eq(5)
    end

    it "lists files with no mutation subjects as subjectless" do
      write("lib/empty.rb", "# only a comment\n")
      result = guess_all
      expect(result.subjectless).to eq(["lib/empty.rb"])
      expect(result.unmatched).not_to include("lib/empty.rb")
    end

    it "narrows to the files the include patterns name" do
      result = guess_all(include: ["lib/a.rb"])
      expect(result.specs).to eq(["spec/a_spec.rb"])
      expect(result.changed).to eq(1)
    end

    it "reports nothing when no source file is included" do
      result = guess_all(include: ["nope/**/*.rb"])
      expect([result.specs, result.unmatched, result.subjectless, result.changed]).to eq([[], [], [], 0])
    end

    it "counts every included file in the changed total" do
      write("lib/nomethod.rb", "# only a comment\n")
      result = guess_all(include: ["lib/**/*.rb"])
      expect(result.specs).to eq(["spec/a_spec.rb", "spec/deep/b_spec.rb", "spec/lib/e_spec.rb"])
      expect(result.unmatched).to eq(["lib/c.rb"])
      expect(result.subjectless).to eq(["lib/nomethod.rb"])
      expect(result.changed).to eq(5)
    end

    it "ignores included files outside the root" do
      outside = File.realpath(Dir.mktmpdir("saboteur-outside"))
      begin
        File.write(File.join(outside, "ghost.rb"), "class Ghost\n  def m\n    1\n  end\nend\n")
        result = guess_all(include: ["lib/**/*.rb", "../#{File.basename(outside)}/ghost.rb"])
        expect(result.changed).to eq(4)
        expect(result.unmatched + result.subjectless).to all(a_string_starting_with("lib/"))
        expect(result.specs).to all(a_string_starting_with("spec/"))
      ensure
        FileUtils.remove_entry(outside)
      end
    end
  end
  # A gem can keep specs at the spec/ root without mirroring the lib
  # namespace dir: pundit tests lib/pundit/policy_finder.rb in
  # spec/policy_finder_spec.rb (#394).
  it "finds a spec flattened at the spec root when the namespace dir is not mirrored (#394)" do
    write("lib/pundit/policy_finder.rb", changed_source)
    write("spec/policy_finder_spec.rb")
    result = guess
    expect(result.specs).to eq(["spec/policy_finder_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # Both committed, so the changed-spec pickup cannot mask which one the
  # guess itself names.
  it "prefers the mirrored spec when both it and a flattened one exist" do
    write("lib/pundit/policy_finder.rb", base_source)
    write("spec/pundit/policy_finder_spec.rb")
    write("spec/policy_finder_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "both specs")
    write("lib/pundit/policy_finder.rb", changed_source)
    result = guess
    expect(result.specs).to eq(["spec/pundit/policy_finder_spec.rb"])
  end

  # Older gems keep unit specs under a spec/unit/ prefix: shoulda-matchers
  # mirrors the path below it (#393), aasm flattens it (#370).
  it "finds a mirrored spec under a spec/unit prefix (#393)" do
    write("lib/shoulda/matchers/equal.rb", changed_source)
    write("spec/unit/shoulda/matchers/equal_spec.rb")
    result = guess
    expect(result.specs).to eq(["spec/unit/shoulda/matchers/equal_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  it "finds a flattened spec under a spec/unit prefix (#370)" do
    write("lib/aasm/base.rb", changed_source)
    write("spec/unit/base_spec.rb")
    result = guess
    expect(result.specs).to eq(["spec/unit/base_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # A spec tree can mirror the gem namespace but drop directories below
  # it: rubocop-ast tests lib/rubocop/ast/node/block_node.rb in
  # spec/rubocop/ast/block_node_spec.rb, dropping node/ (#586).
  it "finds a spec that drops one directory below the gem namespace (#586)" do
    write("lib/rubocop/ast/node/block_node.rb", changed_source)
    write("spec/rubocop/ast/block_node_spec.rb")
    result = guess
    expect(result.specs).to eq(["spec/rubocop/ast/block_node_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # Deeper drops flatten every directory below the namespace, one at a
  # time from the inside out: rubocop-ast tests
  # lib/rubocop/ast/node/mixin/conditional_node.rb in
  # spec/rubocop/ast/conditional_node_spec.rb.
  it "finds a spec that drops several directories below the gem namespace (#586)" do
    write("lib/rubocop/ast/node/mixin/conditional_node.rb", changed_source)
    write("spec/rubocop/ast/conditional_node_spec.rb")
    result = guess
    expect(result.specs).to eq(["spec/rubocop/ast/conditional_node_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # A repeated namespace segment is still just a mid directory: money
  # tests lib/money/money/allocation.rb in spec/money/allocation_spec.rb.
  it "finds a spec below a doubled namespace segment (#586)" do
    write("lib/money/money/allocation.rb", changed_source)
    write("spec/money/allocation_spec.rb")
    result = guess
    expect(result.specs).to eq(["spec/money/allocation_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # Both committed, so the changed-spec pickup cannot mask which one the
  # guess names. Fewer directories dropped keeps more of the mirrored
  # path, so it is the stronger guess.
  it "prefers the drop of fewer directories when several flattened specs exist (#586)" do
    write("lib/rubocop/ast/node/mixin/conditional_node.rb", base_source)
    write("spec/rubocop/ast/node/conditional_node_spec.rb")
    write("spec/rubocop/ast/conditional_node_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "two flattened specs")
    write("lib/rubocop/ast/node/mixin/conditional_node.rb", changed_source)
    result = guess
    expect(result.specs).to eq(["spec/rubocop/ast/node/conditional_node_spec.rb"])
  end

  # Same committed fixture: the namespace-anchored drop beats the bare
  # basename, which keeps none of the mirrored path below the namespace.
  it "prefers a mid-directory drop over the basename at the spec root (#586)" do
    write("lib/rubocop/ast/node/block_node.rb", base_source)
    write("spec/rubocop/ast/block_node_spec.rb")
    write("spec/block_node_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "both specs")
    write("lib/rubocop/ast/node/block_node.rb", changed_source)
    result = guess
    expect(result.specs).to eq(["spec/rubocop/ast/block_node_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # A spec tree can strip directories the convention keeps: aasm tests
  # lib/aasm/core/invokers/proc_invoker.rb in
  # spec/unit/invokers/proc_invoker_spec.rb, dropping the aasm and core
  # segments and adding a unit/ prefix (#600). All four specs commit the
  # spec files, so the changed-spec pickup cannot mask which one the
  # guess itself names.
  it "finds a spec whose tree strips nested namespace directories (#600)" do
    write("lib/aasm/core/invokers/proc_invoker.rb", base_source)
    write("spec/unit/invokers/proc_invoker_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "nested strip layout")
    write("lib/aasm/core/invokers/proc_invoker.rb", changed_source)
    result = guess
    expect(result.specs).to eq(["spec/unit/invokers/proc_invoker_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # The parent directory and basename are the only anchor such layouts
  # keep: two matches make the layout ambiguous, and a wrong guess runs
  # the wrong specs, which reads as a false verdict - worse than the
  # stop, whose near-miss hint then names the candidates.
  it "stops and names the candidates when two specs share the parent dir and basename (#600)" do
    write("lib/x/core/y/z.rb", base_source)
    write("spec/unit/y/z_spec.rb")
    write("spec/other/y/z_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "ambiguous layout")
    write("lib/x/core/y/z.rb", changed_source)
    result = guess
    expect(result.specs).to eq([])
    expect(result.unmatched).to eq(["lib/x/core/y/z.rb"])
    expect(result.unmatched_message).to include(
      "lib/x/core/y/z.rb (expected spec/x/core/y/z_spec.rb; found: spec/other/y/z_spec.rb, spec/unit/y/z_spec.rb)"
    )
  end

  # The anchor is the parent directory and the basename together, never
  # the basename alone: a lone same-basename spec stays a near-miss
  # hint, not a guess.
  it "does not guess a same-basename spec without the parent directory (#600)" do
    write("lib/shop.rb", base_source)
    write("spec/other/shop_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "basename only")
    write("lib/shop.rb", changed_source)
    result = guess
    expect(result.specs).to eq([])
    expect(result.unmatched).to eq(["lib/shop.rb"])
  end

  # The unique match qualifies under any prefix the tree uses, not only
  # unit/: dry-validation keeps specs under spec/integration (#600).
  it "finds a unique spec under an arbitrary prefix with the parent dir and basename (#600)" do
    write("lib/x/y/z.rb", base_source)
    write("spec/integration/y/z_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "integration layout")
    write("lib/x/y/z.rb", changed_source)
    result = guess
    expect(result.specs).to eq(["spec/integration/y/z_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # Only the full parent-directory-plus-basename suffix anchors the
  # guess: a same-basename spec under a different parent does not
  # compete with the real match (#600).
  it "anchors on the parent directory, not the basename alone (#600)" do
    write("lib/x/core/y/z.rb", base_source)
    write("spec/unit/y/z_spec.rb")
    write("spec/other/w/z_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "same basename, different parents")
    write("lib/x/core/y/z.rb", changed_source)
    result = guess
    expect(result.specs).to eq(["spec/unit/y/z_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # The search stays inside the file's own pack: a pack spec root is the
  # pack's spec directory, never the app-wide one (#600).
  it "finds a stripped-layout spec inside the file's own pack (#600)" do
    write("packs/billing/package.yml", "enforce_dependencies: true\n")
    write("packs/billing/lib/core/invokers/proc_invoker.rb", base_source)
    write("packs/billing/spec/unit/invokers/proc_invoker_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "pack with stripped layout")
    write("packs/billing/lib/core/invokers/proc_invoker.rb", changed_source)
    result = guess(include: ["packs/**/*.rb"])
    expect(result.specs).to eq(["packs/billing/spec/unit/invokers/proc_invoker_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # A file outside the source roots keeps its literal guess only: the
  # suffix anchor would guess any same-named spec (#600).
  # With the pack prefix the glob roots at the pack's spec directory: a
  # same-suffix spec elsewhere in the pack is not a candidate (#701
  # dogfood).
  it "roots a pack's suffix guess in the pack's spec directory only (#600)" do
    write("packs/billing/package.yml", "enforce_dependencies: true\n")
    write("packs/billing/lib/core/y/z.rb", base_source)
    write("packs/billing/spec/unit/y/z_spec.rb")
    write("packs/billing/components/y/z_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "pack spec and decoy")
    write("packs/billing/lib/core/y/z.rb", changed_source)
    result = guess(include: ["packs/**/*.rb"])
    expect(result.specs).to eq(["packs/billing/spec/unit/y/z_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # The fallback spec root is spec/, not the whole tree: a same-suffix
  # spec outside spec/ is not a candidate (#701 dogfood).
  it "roots a suffix guess in spec/, not elsewhere in the tree (#600)" do
    write("lib/x/core/y/z.rb", base_source)
    write("spec/unit/y/z_spec.rb")
    write("other/y/z_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "spec and outside decoy")
    write("lib/x/core/y/z.rb", changed_source)
    result = guess
    expect(result.specs).to eq(["spec/unit/y/z_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  # A directory can end in _spec.rb: it is not a spec file, so it must not
  # be guessed (#701 dogfood).
  it "ignores a directory named like a spec (#600)" do
    write("lib/x/core/y/z.rb", base_source)
    FileUtils.mkdir_p(File.join(dir, "spec/unit/y/z_spec.rb"))
    git("add", ".")
    git("commit", "-q", "-m", "spec-looking directory")
    write("lib/x/core/y/z.rb", changed_source)
    result = guess
    expect(result.specs).to eq([])
    expect(result.unmatched).to eq(["lib/x/core/y/z.rb"])
  end

  it "refuses a suffix guess for a file outside the source roots (#600)" do
    write("vendor/a/b/c.rb", base_source)
    write("spec/x/b/c_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "vendor layout")
    write("vendor/a/b/c.rb", changed_source)
    result = guess(include: ["vendor/**/*.rb"])
    expect(result.specs).to eq([])
    expect(result.unmatched).to eq(["vendor/a/b/c.rb"])
  end

  # A parent directory is data, not a pattern: glob metacharacters in it
  # must match literally, or the unique match is silently lost (#600).
  it "matches a parent directory with glob metacharacters literally (#600)" do
    write("lib/x/core/y[1]/z.rb", base_source)
    write("spec/unit/y[1]/z_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "metachar parent")
    write("lib/x/core/y[1]/z.rb", changed_source)
    result = guess
    expect(result.specs).to eq(["spec/unit/y[1]/z_spec.rb"])
    expect(result.unmatched).to eq([])
  end

  describe "Result#out_of_scope_message (#483)" do
    def message_for(count)
      files = Array.new(count) { |index| "engines/e#{index}/lib/f.rb" }
      described_class::Result.new(specs: [], unmatched: [], subjectless: [], changed: 0, hints: {},
                                  changed_specs: [], skipped_specs: {}, out_of_scope: files,
                                  excluded: []).out_of_scope_message
    end

    def message_text(named)
      "no changed source file lies inside the include scope, so nothing ran. " \
        "Changed source files outside it: #{named}. Extend include to cover them, " \
        "or re-run the same command with one --test per existing spec path."
    end

    def first_names(count)
      Array.new(count) { |index| "engines/e#{index}/lib/f.rb" }.join(", ")
    end

    it "names two files joined by a comma and a space" do
      expect(message_for(2)).to eq(message_text(first_names(2)))
    end

    it "names exactly ten files in full with no remainder" do
      expect(message_for(10)).to eq(message_text(first_names(10)))
    end

    it "names the first ten and counts one more at eleven" do
      expect(message_for(11)).to eq(message_text("#{first_names(10)} and 1 more"))
    end

    it "counts the remainder past ten" do
      expect(message_for(13)).to eq(message_text("#{first_names(10)} and 3 more"))
    end
  end

  # The cold-start fallback: a file with no conventional spec and no changed
  # spec used to stop the run. A spec that reads the constant the file
  # defines is a better guess than none, so it runs, and the run says so.
  describe "constant-reference fallback" do
    let(:verifier) do
      "module JWT\n  module Claims\n    class DecodeVerifier\n      def call\n        %d\n      end\n    " \
        "end\n  end\nend\n"
    end
    let(:path) { "lib/jwt/claims/decode_verifier.rb" }

    def commit_then_change(spec_text, spec_path: "spec/features/auth_spec.rb")
      write(path, format(verifier, 1))
      write(spec_path, spec_text) if spec_text
      git("add", ".")
      git("commit", "-q", "-m", "base")
      write(path, format(verifier, 2))
    end

    it "runs the specs that read the file's constant instead of stopping" do
      commit_then_change("RSpec.describe \"auth\" do\n  it(\"x\") { JWT::Claims::DecodeVerifier.new.call }\nend\n")
      result = guess

      expect(result.unmatched).to eq([])
      expect(result.specs).to include("spec/features/auth_spec.rb")
      expect(result.referenced).to eq(path => ["spec/features/auth_spec.rb"])
      expect(result.referenced_message).to include("selected by constant reference or require", path,
                                                   "spec/features/auth_spec.rb")
    end

    it "lists every file with its specs in the note, in the stated shape" do
      result = described_class::Result.new(specs: [], unmatched: [], subjectless: [], changed: [], hints: {},
                                           referenced: { "lib/a.rb" => %w[spec/x_spec.rb spec/y_spec.rb],
                                                         "lib/b.rb" => %w[spec/z_spec.rb spec/w_spec.rb] })

      expect(result.referenced_message).to eq(
        "inferred specs: selected by constant reference or require, not by name: " \
        "lib/a.rb (spec/x_spec.rb, spec/y_spec.rb), lib/b.rb (spec/z_spec.rb, spec/w_spec.rb); " \
        "a spec that reaches the file another way is not found"
      )
    end

    describe "#reference_specs" do
      let(:instance) do
        described_class.new(Saboteur::Config.new({ "include" => ["lib/**/*.rb"] }, root: dir))
      end

      it "does not list the suite when no file is unmatched" do
        expect(instance).not_to receive(:suite_files)

        expect(instance.send(:reference_specs, [])).to eq({})
      end

      it "returns nothing when RSpec cannot list the suite" do
        allow(instance).to receive(:suite_files).and_return(nil)
        write(path, format(verifier, 1))

        expect(instance.send(:reference_specs, [path])).to eq({})
      end
    end

    it "also takes a spec that requires the file by its load path, with no constant read" do
      commit_then_change("require \"jwt/claims/decode_verifier\"\nRSpec.describe(\"a\") { it(\"x\") { JWT.decode } }\n")

      expect(guess.referenced).to eq(path => ["spec/features/auth_spec.rb"])
    end

    it "also takes a spec that require_relatives the file" do
      commit_then_change("require_relative \"../../lib/jwt/claims/decode_verifier\"\nRSpec.describe(\"a\") { 1 }\n")

      expect(guess.referenced).to eq(path => ["spec/features/auth_spec.rb"])
    end

    it "does not take a spec whose require names only the same basename or resolves elsewhere" do
      commit_then_change("require \"decode_verifier\"\nrequire_relative \"../lib/jwt/claims/decode_verifier\"\n" \
                         "RSpec.describe(\"a\") { it(\"x\") { 1 } }\n")

      expect(guess.unmatched).to eq([path])
    end

    it "still stops when no spec reads the constant" do
      commit_then_change("RSpec.describe \"auth\" do\n  it(\"x\") { JWT.decode }\nend\n")

      expect(guess.unmatched).to eq([path])
      expect(guess.referenced).to eq({})
    end

    it "still stops for a hub constant read by more specs than the cap" do
      12.times do |n|
        write("spec/features/read#{n}_spec.rb",
              "RSpec.describe \"r\" do\n  it(\"x\") { JWT::Claims::DecodeVerifier }\nend\n")
      end
      commit_then_change(nil)
      result = guess

      expect(result.unmatched).to eq([path])
      expect(result.unmatched_message).to include("(expected spec/jwt/claims/decode_verifier_spec.rb; " \
                                                  "12 specs reference or require it, over the cap of 10)")
    end

    it "names the same-named specs before the reader count in one stop line" do
      result = described_class::Result.new(specs: [], unmatched: ["lib/a.rb"], subjectless: [], changed: [],
                                           hints: { "lib/a.rb" => "spec/a_spec.rb" },
                                           near: { "lib/a.rb" => ["spec/unit/a_spec.rb"] },
                                           crowded: { "lib/a.rb" => 11 })

      expect(result.unmatched_message).to include(
        "lib/a.rb (expected spec/a_spec.rb; found: spec/unit/a_spec.rb; " \
        "11 specs reference or require it, over the cap of 10)"
      )
    end

    it "says nothing about readers when none read the constant" do
      commit_then_change("RSpec.describe \"auth\" do\n  it(\"x\") { JWT.decode }\nend\n")

      expect(guess.unmatched_message).not_to include("reference or require it")
    end

    it "still stops when a same-named spec exists elsewhere: the choice is the user's (#658)" do
      commit_then_change("RSpec.describe \"auth\" do\n  it(\"x\") { JWT::Claims::DecodeVerifier }\nend\n")
      write("spec/unit/jwt/decode_verifier_spec.rb")
      git("add", ".")

      expect(guess.unmatched).to eq([path])
      expect(guess.referenced).to eq({})
    end

    it "leaves a file with a conventional spec alone" do
      commit_then_change("RSpec.describe \"auth\" do\n  it(\"x\") { JWT::Claims::DecodeVerifier }\nend\n")
      write("spec/jwt/claims/decode_verifier_spec.rb")
      result = guess

      expect(result.referenced).to eq({})
      expect(result.specs).to eq(["spec/jwt/claims/decode_verifier_spec.rb"])
    end
  end

  describe "names that carry a newline in the stop and warning messages (#834)" do
    let(:evil) { "lib/x\n::error::y.rb" }
    let(:result) do
      described_class::Result.new(
        specs: [], unmatched: [evil], subjectless: [evil], changed: [evil], excluded: [evil], out_of_scope: [evil],
        hints: { evil => "spec/x\n::error::y_spec.rb" }, changed_specs: ["spec/c\n::error::s_spec.rb"],
        skipped_specs: { "spec/k\n::error::s_spec.rb" => "gone" }, near: { evil => ["spec/n\n##[error]s_spec.rb"] },
        without_map_entry: [evil]
      )
    end

    it "starts no line of any message with a CI workflow command" do
      messages = [result.unmatched_message, result.unmatched_warning(evil), result.skipped_message,
                  result.subjectless_message(since: false), result.excluded_message, result.out_of_scope_message]
      lines = messages.flat_map(&:lines).map(&:lstrip)
      expect(lines.grep(/\A(::|##\[)/)).to be_empty
      expect(messages.join).to include("lib/x\\x0a::error::y.rb")
    end
  end

  describe "Result messages" do
    def result_with(**fields)
      described_class::Result.new(specs: [], unmatched: [], subjectless: [], changed: 0, hints: {}, **fields)
    end

    it "joins the skipped specs with a comma and a space" do
      result = result_with(skipped_specs: { "spec/a_spec.rb" => "gone", "spec/b_spec.rb" => "empty" })

      expect(result.skipped_message).to eq(
        "inferred specs: not running spec files changed in the diff: " \
        "spec/a_spec.rb (gone), spec/b_spec.rb (empty)"
      )
    end

    it "says it has, not they have, for a single subjectless file (P6)" do
      result = result_with(subjectless: %w[lib/a.rb])

      expect(result.subjectless_message(since: false))
        .to eq("inferred specs: no spec is required for lib/a.rb: it has no mutation subjects")
    end

    it "names the subjectless files and says why, with and without --since" do
      result = result_with(subjectless: %w[lib/a.rb lib/b.rb])
      lead = "inferred specs: no spec is required for lib/a.rb, lib/b.rb: they have "

      expect(result.subjectless_message(since: true)).to eq("#{lead}no changed mutation subjects")
      expect(result.subjectless_message(since: false)).to eq("#{lead}no mutation subjects")
    end

    it "joins the specs changed in the diff with a comma and a space" do
      result = result_with(specs: %w[spec/a_spec.rb spec/b_spec.rb], changed_specs: %w[spec/a_spec.rb spec/b_spec.rb])

      expect(result.scope_message(since: true)).to start_with(
        "inferred specs: running only spec/a_spec.rb, spec/b_spec.rb " \
        "(changed in the diff: spec/a_spec.rb, spec/b_spec.rb). "
      )
    end
  end

  describe "guessing for named subjects under --since" do
    it "keeps a file whose class is named by a pattern that is a prefix of its subject ids" do
      write("lib/a.rb", changed_source)
      config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["lib/**/*.rb"] }, root: dir)

      expect(described_class.new(config).call_for(["lib/a.rb"], ["Widget"]).specs).to eq(["spec/a_spec.rb"])
    end
  end

  describe "candidates for a file under app/" do
    it "also tries the full path as a spec directory, spec/app/models/x_spec.rb" do
      write("app/models/x.rb", changed_source)
      write("spec/app/models/x_spec.rb")
      write("spec/other/models/x_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "x")
      write("app/models/x.rb", base_source)

      expect(guess(include: ["app/**/*.rb"]).specs).to eq(["spec/app/models/x_spec.rb"])
    end
  end
end
