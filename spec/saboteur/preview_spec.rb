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

  it "announces the effective operator set" do
    preview(config).call
    expect(out.string).to match(/^Operators: \w+(, \w+)+/)
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

  it "gives no estimate when durations are infinite or their total overflows" do
    settings = config(operators: ["arithmetic"])
    FileUtils.mkdir_p(File.join(root, ".saboteur"))
    identity = Saboteur::Engine::RunFingerprint.new(config: settings).snapshot.digest
    map = File.join(root, ".saboteur", "big.json")
    format = Saboteur::Selection::CoverageMap::FORMAT
    %w[1e999 1e308].each do |duration|
      File.write(map, %({"format":#{format.to_json},"tests":["t"],"lines":{#{target.file.to_json}:{"3":[0]}},) +
                      %("durations":[#{duration}]}))
      File.write(File.join(root, ".saboteur", "preview.json"), JSON.generate(path: map, fingerprint: identity))
      out.truncate(0)
      preview(settings).call
      expect(out.string).to include("Total: 2 mutants", "no estimate: cached test durations are incomplete")
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
