# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Preview do
  it "reads a receipt naming a non-ASCII map path under a non-UTF-8 locale" do
    cfg = config
    dir = cfg.path("cache_dir")
    FileUtils.mkdir_p(dir)
    digest = Saboteur::Engine::RunFingerprint.new(config: cfg).snapshot.digest
    File.write(File.join(dir, "preview.json"),
               JSON.generate({ "fingerprint" => digest, "path" => "/tmp/caf\u00E9/map.json" }))
    map = instance_double(Saboteur::Selection::CoverageMap)
    allow(Saboteur::Selection::CoverageMap).to receive(:load).with("/tmp/caf\u00E9/map.json").and_return(map)
    allow(File).to receive(:read).and_wrap_original do |original, *args|
      original.call(*args).force_encoding(Encoding::US_ASCII)
    end
    expect(preview(cfg).send(:cached_map)).to be(map)
  end

  let(:target) { subjects_in("class PreviewCases\n  def m(x)\n    x + 1\n    x * 2\n  end\nend\n").first }
  let(:root) { File.dirname(target.file) }
  let(:out) { StringIO.new }

  def config(**settings)
    Saboteur::Config.new({ "include" => ["*.rb"] }.merge(settings.transform_keys(&:to_s)), root: root)
  end

  def preview(settings = config)
    described_class.new(settings, out: out, err: StringIO.new)
  end

  it "prints exact omissions above and at the method cap" do
    full = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new],
                                            Saboteur::Engine::Diagnostics.new(StringIO.new)).for(target).size
    preview(config(max_mutants_per_method: 1)).call
    expect(out.string).to include("Total: 1 mutants; #{full - 1} dropped")
    out.truncate(0)
    preview(config(max_mutants_per_method: full + 1)).call
    expect(out.string).to include("Total: #{full} mutants; 0 dropped")
    out.truncate(0)
    preview(config(max_mutants_per_method: full)).call
    expect(out.string).to include("Total: #{full} mutants; 0 dropped")
  end

  it "leads with the totals, not the default operator list (#1178)" do
    preview(config).call
    expect(out.string).not_to include("Operators:")
    expect(out.string).to include("Total: ")
  end

  it "announces the effective operator set when the selection is changed" do
    preview(config(operators: %w[arithmetic range])).call
    expect(out.string).to start_with("Operators: arithmetic, range\n")
    out.truncate(0)
    out.rewind
    preview(config(exclude_operators: %w[range])).call
    expect(out.string).to match(/\AOperators: \w+(, \w+)+\n/)
    expect(out.string.lines.first).not_to include("range")
  end

  it "keeps the json inventory free of the operator line even when the selection is changed" do
    Saboteur::Preview.new(config(operators: %w[arithmetic], verbose: true), out: out, err: StringIO.new,
                                                                            format: "json").call
    expect { JSON.parse(out.string) }.not_to raise_error
    expect(out.string).not_to include("Operators:")
  end

  it "announces the effective operator set under --verbose" do
    preview(config(verbose: true)).call
    expect(out.string).to match(/\AOperators: \w+(, \w+)+\n/)
  end

  it "prints the shard slice with the full inventory digest" do
    preview(config).call
    full = out.string[/Total: (\d+) mutants/, 1].to_i
    out.truncate(0)

    totals = (1..3).map do |index|
      preview(config(shard: "#{index}/3")).call
      expect(out.string).to include("Shard #{index}/3:", "inventory sha256:", "partial run")
      selected = out.string[/Total: (\d+) mutants/, 1].to_i
      out.truncate(0)
      selected
    end
    expect(totals.sum).to eq(full)
  end

  it "uses diff lines both to select methods and to restrict their candidates" do
    allow(Saboteur::Selection::GitDiff).to receive(:line_maps)
      .with("base", root: root, include: anything, diagnostics: anything)
      .and_return(Saboteur::Selection::GitDiff::LineMaps.new(changed: { target.file => [4] },
                                                             behavior: { target.file => [4] }))
    allow(Saboteur::Selection::GitDiff).to receive(:merge_base).and_return("base")
    allow(Saboteur::Selection::GitDiff).to receive(:file_at).and_return(nil)
    allow(Saboteur::Selection::GitDiff).to receive(:deletion_only_files).and_return([])
    allow(Saboteur::Selection::UntrackedChanges).to receive(:paths).and_return([])
    scoped = config(since: "base")
    selection = Saboteur::Engine::SubjectSelection.new(scoped, Saboteur::Engine::Diagnostics.new(StringIO.new))
    subjects = selection.select(scoped.included_files)
    all = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new],
                                           Saboteur::Engine::Diagnostics.new(StringIO.new)).for(subjects.first)
    expected = Saboteur::Engine::DiffScope.new(selection.behavior_lines).restrict(subjects.first, all).size
    preview(scoped).call
    expect(out.string).to include("Total: #{expected} mutants")
  end

  it "keeps the configured hazard guard unless explicitly allowed" do
    File.write(target.file, "class PreviewCases\n  def m\n    FileUtils.rm_rf(\"tmp\")\n  end\nend\n")
    settings = config
    preview(settings).call
    suppressed = out.string[/Total: (\d+)/, 1].to_i
    out.truncate(0)
    preview(config(allow_hazardous: true)).call
    expect(out.string[/Total: (\d+)/, 1].to_i).to be > suppressed
  end

  it "prints discovery warnings and marks the total incomplete, without an estimate" do
    File.write(target.file, "def broken(")
    preview.call
    expect(out.string).to include("does not parse", "INCOMPLETE: 1 file(s) could not be parsed",
                                  "no estimate: source discovery was incomplete")
  end

  it "does not mark a clean discovery incomplete" do
    preview.call
    expect(out.string).not_to include("INCOMPLETE", "Inline suppressions:")
  end

  [
    ['def m(x); x + 1; end # saboteur:disable-line reason="all candidates"', true],
    ['def m(x); x + 1; end # saboteur:disable-line arithmetic reason="operator subset"', false]
  ].each do |definition, all|
    it "audits #{all ? 'all' : 'a subset of'} inline-suppressed candidates without boot or writes" do
      File.write(target.file, "class PreviewCases\n  #{definition}\nend\n")
      settings = config
      subject = Saboteur::SubjectFinder.new.call(target.file).subjects.first
      diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
      candidates = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics).for(subject)
      entries = diagnostics.inline_suppressions
      expect(entries).not_to be_empty
      expect(candidates.empty?).to eq(all)
      before = Dir.glob("#{root}/**/*", File::FNM_DOTMATCH).select { |file| File.file?(file) }
                  .to_h { |file| [file, File.binread(file)] }
      expect(Saboteur::Engine).not_to receive(:new)
      preview(settings).call
      expect(out.string).to include("Total: #{candidates.size} mutants",
                                    "Inline suppressions: #{entries.size} candidates in selected methods",
                                    "before diff restriction and per-method cap; outside the planned total")
      entries.each do |entry|
        expect(out.string).to include("#{File.basename(subject.file)}:#{entry[:line]} #{entry[:subject]} " \
                                      "#{entry[:operator]} #{entry[:digest]}: #{entry[:reason]}")
      end
      after = Dir.glob("#{root}/**/*", File::FNM_DOTMATCH).select { |file| File.file?(file) }
                 .to_h { |file| [file, File.binread(file)] }
      expect(after).to eq(before)
    end
  end

  def receipt(settings, durations: { "t1" => 0.25 }, fingerprint: nil)
    map = Saboteur::Selection::CoverageMap.new(lines: { target.file => { 3 => ["t1"] } }, tests: ["t1"],
                                               durations: durations)
    cache = File.join(root, ".saboteur", "coverage.json")
    map.save(cache)
    identity = fingerprint || Saboteur::Engine::RunFingerprint.new(config: settings).snapshot.digest
    File.write(File.join(root, ".saboteur", "preview.json"), JSON.generate(path: cache, fingerprint: identity))
  end

  it "says estimates need the in-process mode under --test-command, which never builds a map (#590)" do
    settings = config(test_command: "bin/rails test")
    preview(settings).call
    expect(out.string).to include("no estimate: --test-command runs never build a coverage map; " \
                                  "estimates need the in-process rspec mode")
  end

  it "rejects stale estimates and reports missing durations" do
    settings = config
    receipt(settings, fingerprint: "old")
    preview(settings).call
    expect(out.string).to include("no estimate: run once")
    out.truncate(0)
    receipt(settings, durations: {})
    preview(settings).call
    expect(out.string).to include("no estimate: cached test durations are incomplete")
  end

  it "computes work for every planned mutant from unrounded cached durations" do
    settings = config(operators: ["arithmetic"])
    receipt(settings, durations: { "t1" => 0.123456 })
    preview(settings).call
    expect(out.string).to include("Total: 2 mutants", "Estimated baseline covering-test work: 0.25 s",
                                  "not a bound on mutant runtime")
  end

  it "reports a corrupt receipt without making changes" do
    FileUtils.mkdir_p(File.join(root, ".saboteur"))
    path = File.join(root, ".saboteur", "preview.json")
    File.write(path, "{")
    preview.call
    expect(out.string).to include("no estimate: run once")
    expect(File.read(path)).to eq("{")
  end
  it "reports no estimate for valid JSON receipts of the wrong shape or a missing map" do
    settings = config
    FileUtils.mkdir_p(File.join(root, ".saboteur"))
    path = File.join(root, ".saboteur", "preview.json")
    identity = Saboteur::Engine::RunFingerprint.new(config: settings).snapshot.digest
    ["[]", "null", "42", JSON.generate(path: 1, fingerprint: identity), JSON.generate(path: "x", fingerprint: 1),
     JSON.generate(path: File.join(root, "absent.json"), fingerprint: identity),
     JSON.generate(path: root, fingerprint: identity)].each do |body|
      File.write(path, body)
      out.truncate(0)
      expect { preview(settings).call }.not_to raise_error
      expect(out.string).to include("no estimate: run once")
    end
  end

  it "reports no estimate when the coverage map itself has the wrong shape" do
    settings = config
    FileUtils.mkdir_p(File.join(root, ".saboteur"))
    identity = Saboteur::Engine::RunFingerprint.new(config: settings).snapshot.digest
    map = File.join(root, ".saboteur", "bad.json")
    [{ format: Saboteur::Selection::CoverageMap::FORMAT, tests: 1, lines: [], durations: [] },
     { format: Saboteur::Selection::CoverageMap::FORMAT, tests: ["t"], lines: { "f" => { "1" => [5] } },
       durations: [] }].each do |body|
      File.write(map, JSON.generate(body))
      File.write(File.join(root, ".saboteur", "preview.json"), JSON.generate(path: map, fingerprint: identity))
      out.truncate(0)
      expect { preview(settings).call }.not_to raise_error
      expect(out.string).to include("no estimate: run once")
    end
  end

  it "reports incomplete durations, not an error, for a map that decodes but holds unusable values" do
    settings = config(operators: ["arithmetic"])
    FileUtils.mkdir_p(File.join(root, ".saboteur"))
    identity = Saboteur::Engine::RunFingerprint.new(config: settings).snapshot.digest
    map = File.join(root, ".saboteur", "late.json")
    format = Saboteur::Selection::CoverageMap::FORMAT
    base = { format: format, tests: ["t"], lines: { target.file => { "3" => [0] } } }
    [{ durations: ["bad"] }, { durations: [-1.0] }, { durations: [nil] }, { durations: {} },
     { tests: %w[t u], durations: [0.5, -1.0] },
     { durations: [0.5], methods: 5 }, { durations: [0.5], load_lines: [1] }].each do |extra|
      File.write(map, JSON.generate(base.merge(extra)))
      File.write(File.join(root, ".saboteur", "preview.json"), JSON.generate(path: map, fingerprint: identity))
      out.truncate(0)
      expect { preview(settings).call }.not_to raise_error
      expect(out.string).to include("Total: 2 mutants")
      expect(out.string).to match(/no estimate: (cached test durations are incomplete|run once)/)
      expect(out.string).not_to include("Estimated baseline")
    end
  end

  it "gives no estimate when a duration is infinite or the total overflows" do
    settings = config(operators: ["arithmetic"])
    FileUtils.mkdir_p(File.join(root, ".saboteur"))
    identity = Saboteur::Engine::RunFingerprint.new(config: settings).snapshot.digest
    map = File.join(root, ".saboteur", "big.json")
    format = Saboteur::Selection::CoverageMap::FORMAT
    # An infinite duration is rejected when the map loads; a finite one that only
    # overflows the total still loads and is refused by the estimate.
    { "1e999" => "no estimate: run once to build the coverage map",
      "1e308" => "no estimate: cached test durations are incomplete" }.each do |duration, message|
      File.write(map, %({"format":#{format.to_json},"tests":["t"],"lines":{#{target.file.to_json}:{"3":[0]}},) +
                      %("durations":[#{duration}]}))
      File.write(File.join(root, ".saboteur", "preview.json"), JSON.generate(path: map, fingerprint: identity))
      out.truncate(0)
      preview(settings).call
      expect(out.string).to include("Total: 2 mutants", message)
      expect(out.string).not_to include("Estimated baseline", "Infinity")
    end
  end

  it "still estimates from a map whose durations are valid" do
    settings = config(operators: ["arithmetic"])
    receipt(settings, durations: { "t1" => 0.0 })
    preview(settings).call
    expect(out.string).to include("Estimated baseline covering-test work: 0.0 s")
  end

  it "uses a replaced hazard list rather than the default" do
    settings = config(hazard: ["x.+"])
    guard = instance_double(Saboteur::MutationSource::HazardGuard)
    expect(Saboteur::MutationSource::HazardGuard).to receive(:new).with(["x.+"]).and_return(guard)
    allow(guard).to receive(:partition) { |list, _subject| [list, []] }
    preview(settings).call
  end
end

RSpec.describe "Saboteur::Preview json inventory" do
  let(:target) { subjects_in("class PreviewCases\n  def m(x)\n    x + 1\n    x * 2\n  end\nend\n").first }
  let(:root) { File.dirname(target.file) }
  let(:out) { StringIO.new }

  def config(**settings)
    Saboteur::Config.new({ "include" => ["*.rb"] }.merge(settings.transform_keys(&:to_s)), root: root)
  end

  def json_preview(settings = config)
    Saboteur::Preview.new(settings, out: out, err: StringIO.new, format: "json")
  end

  def payload
    JSON.parse(out.string)
  end

  it "emits a versioned inventory naming each planned mutant with location and edits" do
    json_preview.call
    expect(payload["schema_version"]).to eq(1)
    expect(payload["saboteur_version"]).to eq(Saboteur::VERSION)
    expect(payload["mode"]).to eq("dry-run")
    expect(payload["test_selection"]).to eq("auto")
    expect(payload["mutants"]).not_to be_empty
    expect(payload["totals"]["mutants"]).to eq(payload["mutants"].size)
    entry = payload["mutants"].first
    expect(entry).to include("subject" => "PreviewCases#m")
    expect(entry["digest"]).to match(/\A[0-9a-f]{16}\z/)
    expect(entry["line"]).to be_between(3, 4)
    edit = entry["edits"].first
    expect(edit["start_byte"]).to be <= edit["end_byte"]
    expect(edit["original"]).not_to eq(edit["replacement"])
    expect(payload["subjects"]).to eq(
      [{ "id" => "PreviewCases#m", "file" => File.basename(target.file),
         "start_line" => 2, "end_line" => 5, "mutants" => payload["mutants"].size }]
    )
  end

  it "names each planned mutant by the digest a run or --id replay computes" do
    subject = Saboteur::SubjectFinder.new.call(target.file).subjects.first
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    mutations = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics).for(subject)
    expected = mutations.map do |(mutation, _)|
      mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    end
    json_preview.call
    expect(payload["mutants"].map { |entry| entry["digest"] }).to match_array(expected)
  end

  it "records no omission and no skips when the count lands exactly on the method cap" do
    # Kills the list.size > limit -> >= survivor (befe17aff3756612): at
    # list.size == limit the guard must not fire, so not even a count-0
    # omission is recorded.
    full = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new],
                                            Saboteur::Engine::Diagnostics.new(StringIO.new)).for(target).size
    json = json_preview(config(max_mutants_per_method: full))
    json.call
    expect(payload["totals"]["dropped_by_max_mutants_per_method"]).to eq(0)
    expect(payload["skipped"]).to eq([])
    expect(json.instance_variable_get(:@diagnostics).omissions).to eq([])
  end

  it "records no per-mutant skips in text mode when the cap drops mutants" do
    # Kills the record_skip ... if @json -> unconditional survivor
    # (333431ce20d3af65): text mode has no inventory, so no skip entries.
    text = Saboteur::Preview.new(config(max_mutants_per_method: 1), out: out, err: StringIO.new)
    text.call
    expect(out.string).to include("Total: 1 mutants;")
    expect(text.instance_variable_get(:@skipped)).to eq([])
  end

  it "lists mutants dropped by the per-method cap with their digests and reason" do
    json_preview(config(max_mutants_per_method: 1)).call
    expect(payload["totals"]).to include("mutants" => 1)
    expect(payload["totals"]["dropped_by_max_mutants_per_method"]).to be_positive
    expect(payload["skipped"].size).to eq(payload["totals"]["dropped_by_max_mutants_per_method"])
    expect(payload["skipped"].map { |skip| skip["digest"] } & payload["mutants"].map { |entry| entry["digest"] })
      .to eq([])
    expect(payload["skipped"].map { |skip| skip["reason"] }.uniq).to eq(["max_mutants_per_method"])
    expect(payload["skipped"].map { |skip| skip["digest"] }).to all(match(/\A[0-9a-f]{16}\z/))
  end

  it "lists inline-suppressed candidates with the directive reason" do
    File.write(target.file,
               "class PreviewCases\n  def m(x)\n    x + 1 # saboteur:disable-line reason=\"stop\"\n  end\nend\n")
    json_preview.call
    skipped = payload["skipped"]
    expect(skipped).not_to be_empty
    expect(skipped.map { |skip| skip["reason"] }.uniq).to eq(["inline_suppression: stop"])
    expect(skipped.first).to include("subject" => "PreviewCases#m", "line" => 3)
  end

  it "lists hazard-refused candidates" do
    File.write(target.file, "class PreviewCases\n  def m\n    FileUtils.rm_rf(\"tmp\")\n  end\nend\n")
    json_preview.call
    expect(payload["skipped"].map { |skip| skip["reason"] }).to include("hazardous")
  end

  it "keeps stdout parseable when discovery fails and reports the gap in totals" do
    File.write(target.file, "def broken(")
    json_preview.call
    expect(payload["totals"]["incomplete_files"]).to eq(1)
    expect(payload["estimated_seconds"]).to be_nil
  end
end

RSpec.describe Saboteur::Preview, "unsupported subjects (#651)" do
  let(:blocked) do
    subjects_in("class K\n  tap do\n    def blocked(x)\n      x + 1\n    end\n  end\nend\n").first
  end

  %w[text json].each do |format|
    it "excludes block-defined subjects from the #{format} plan without booting" do
      out = StringIO.new
      config = Saboteur::Config.new({ "include" => ["*.rb"] }, root: File.dirname(blocked.file))
      expect(Saboteur::Engine::Boot).not_to receive(:new)
      described_class.new(config, out:, err: StringIO.new, format: format).call
      note = "K#blocked (subject_fixture.rb:3): skipped (defined inside a block); excluded from the planned total"
      if format == "json"
        payload = JSON.parse(out.string)
        expect(payload["totals"]["mutants"]).to eq(0)
        expect(payload["mutants"]).to eq([])
        expect(payload["subjects"].map { |subject| subject["mutants"] }).to eq([0])
        expect(payload["warnings"]).to include(note)
      else
        expect(out.string).to include("Total: 0 mutants; 0 dropped", note)
        expect(out.string).not_to match(/K#blocked  \d+ mutants/)
      end
    end
  end
  it "does not generate candidates for a statically unsupported subject" do
    blocked.skip_reason = "refinements"
    config = Saboteur::Config.new({}, root: File.dirname(blocked.file))
    candidates = instance_double(Saboteur::Engine::Candidates)
    expect(candidates).not_to receive(:for)
    preview = described_class.new(config, out: StringIO.new, err: StringIO.new)
    expect(preview.send(:planned, blocked, candidates, nil)).to eq([])
  end
end
