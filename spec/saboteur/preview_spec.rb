# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Preview do
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

  it "uses diff lines both to select methods and to restrict their candidates" do
    allow(Saboteur::Selection::GitDiff).to receive(:changed_lines).with("base", root: root)
                                                                  .and_return(target.file => [4])
    scoped = config(since: "base")
    selection = Saboteur::Engine::SubjectSelection.new(scoped, Saboteur::Engine::Diagnostics.new(StringIO.new))
    subjects = selection.select(scoped.included_files)
    all = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new],
                                           Saboteur::Engine::Diagnostics.new(StringIO.new)).for(subjects.first)
    expected = Saboteur::Engine::DiffScope.new(selection.changed_lines).restrict(subjects.first, all).size
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
    expect(out.string).not_to include("INCOMPLETE")
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

  it "uses a replaced hazard list rather than the default" do
    settings = config(hazard: ["x.+"])
    guard = instance_double(Saboteur::MutationSource::HazardGuard)
    expect(Saboteur::MutationSource::HazardGuard).to receive(:new).with(["x.+"]).and_return(guard)
    allow(guard).to receive(:partition) { |list, _subject| [list, []] }
    preview(settings).call
  end
end
