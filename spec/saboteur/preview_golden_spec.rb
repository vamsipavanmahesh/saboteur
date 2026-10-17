# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Output-pinning specs for `saboteur run --dry-run` (text and json). Expected
# values come from an independent oracle (Candidates and the file bytes), never
# from the Preview code under test.
RSpec.describe "Saboteur::Preview golden output" do
  let(:source) { "class PreviewCases\n  def m(x)\n    x + 1\n    x * 2\n  end\nend\n" }
  let(:target) { subjects_in(source).first }
  let(:root) { File.dirname(target.file) }
  let(:base) { File.basename(target.file) }
  let(:out) { StringIO.new }

  def config(**settings)
    Saboteur::Config.new({ "include" => ["*.rb"] }.merge(settings.transform_keys(&:to_s)), root: root)
  end

  def run_preview(settings = config, format: "text")
    out.truncate(0)
    out.rewind
    Saboteur::Preview.new(settings, out: out, err: StringIO.new, format: format).call
  end

  def payload
    JSON.parse(out.string)
  end

  def oracle_subject
    Saboteur::SubjectFinder.new.call(target.file).subjects.first
  end

  def oracle_candidates(settings = config, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new))
    guard = Saboteur::MutationSource::HazardGuard.new(settings["hazard"]) unless settings["allow_hazardous"]
    Saboteur::Engine::Candidates.new(Saboteur::Engine::Candidates.build_sources(settings), diagnostics,
                                     hazard_guard: guard).for(oracle_subject)
  end

  def receipt(settings, durations)
    map = Saboteur::Selection::CoverageMap.new(lines: { target.file => { 3 => ["t1"] } }, tests: ["t1"],
                                               durations: durations)
    FileUtils.mkdir_p(File.join(root, ".saboteur"))
    cache = File.join(root, ".saboteur", "coverage.json")
    map.save(cache)
    identity = Saboteur::Engine::RunFingerprint.new(config: settings).snapshot.digest
    File.write(File.join(root, ".saboteur", "preview.json"), JSON.generate(path: cache, fingerprint: identity))
  end

  describe "text" do
    it "prints one exact line per planned subject" do
      full = oracle_candidates.size
      run_preview
      expect(out.string.lines).to include("#{base}:2 PreviewCases#m  #{full} mutants\n")
    end

    it "prints the total line with the cap omission count" do
      run_preview(config(max_mutants_per_method: 1))
      expect(out.string).to include("#{base}:2 PreviewCases#m  1 mutants\n")
      expect(out.string.lines.grep(/\ATotal:/).size).to eq(1)
    end

    it "indents each inline suppression row under its header" do
      File.write(target.file,
                 "class PreviewCases\n  def m(x)\n    x + 1 # saboteur:disable-line reason=\"stop\"\n  end\nend\n")
      diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
      oracle_candidates(diagnostics: diagnostics)
      entries = diagnostics.inline_suppressions
      expect(entries).not_to be_empty
      run_preview
      entries.each do |entry|
        row = "  #{base}:#{entry[:line]} #{entry[:subject]} #{entry[:operator]} #{entry[:digest]}: #{entry[:reason]}\n"
        expect(out.string.lines).to include(row)
      end
    end
  end

  describe "json" do
    it "pins the top-level shape and key order" do
      run_preview(format: "json")
      expect(payload.keys).to eq(%w[schema_version saboteur_version mode operators test_selection tests subjects
                                    mutants skipped totals estimated_seconds warnings])
      expect(payload["totals"].keys).to eq(%w[mutants dropped_by_max_mutants_per_method incomplete_files])
    end

    it "reports the effective operators and the configured tests" do
      settings = config(operators: ["arithmetic"], tests: ["spec/foo_spec.rb"])
      run_preview(settings, format: "json")
      expect(payload["operators"]).to eq(settings.operator_policy["effective"])
      expect(payload["operators"]).to include("arithmetic")
      expect(payload["tests"]).to eq(settings["tests"])
      expect(payload["tests"]).to eq(["spec/foo_spec.rb"])
    end

    it "names every edit with the exact source text, offsets, replacement and operator" do
      settings = config(operators: ["arithmetic"])
      expected = oracle_candidates(settings).map(&:first)
      bytes = File.binread(target.file)
      run_preview(settings, format: "json")
      expect(payload["mutants"].size).to eq(expected.size)
      payload["mutants"].zip(expected).each do |entry, mutation|
        expect(entry["operator"]).to eq("arithmetic")
        expect(entry["operator"]).to eq(mutation.operator.to_s)
        expect(entry["file"]).to eq(base)
        expect(entry["subject"]).to eq("PreviewCases#m")
        expect(entry["edits"].size).to eq(mutation.edits.size)
        entry["edits"].zip(mutation.edits).each do |got, edit|
          span = bytes.byteslice(edit.start_byte, edit.end_byte - edit.start_byte).force_encoding(Encoding::UTF_8)
          expect(got).to eq("start_byte" => edit.start_byte, "end_byte" => edit.end_byte,
                            "original" => span, "replacement" => edit.replacement)
          expect(got["original"]).not_to be_empty
        end
      end
    end

    it "locates the line from the first edit" do
      settings = config(operators: ["arithmetic"])
      run_preview(settings, format: "json")
      lines = payload["mutants"].map { |entry| entry["line"] }
      expect(lines).to all(eq(3).or(eq(4)))
      expect(lines.uniq.sort).to eq([3, 4])
    end

    it "slices multibyte sources by bytes, not characters" do
      # The engine emits no arithmetic mutant for String#+, so the multibyte
      # content precedes the arithmetic instead; the edit offsets then sit
      # past multibyte bytes, where char-based slicing would drift.
      multibyte = "class PreviewCases\n  def m(x)\n    \"\u00E9\u00E9\"\n    x + 1\n    x * 2\n  end\nend\n"
      File.write(target.file, multibyte)
      settings = config(operators: ["arithmetic"])
      bytes = File.binread(target.file)
      subject = Saboteur::SubjectFinder.new.call(target.file).subjects.first
      diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
      guard = Saboteur::MutationSource::HazardGuard.new(settings["hazard"])
      expected = Saboteur::Engine::Candidates
                 .new(Saboteur::Engine::Candidates.build_sources(settings), diagnostics, hazard_guard: guard)
                 .for(subject).map(&:first).flat_map(&:edits)
      run_preview(settings, format: "json")
      got = payload["mutants"].flat_map { |entry| entry["edits"] }
      expect(got).not_to be_empty
      expect(got.map { |edit| edit["original"] }).to eq(
        expected.map { |edit|
          bytes.byteslice(edit.start_byte, edit.end_byte - edit.start_byte).force_encoding("UTF-8")
        }
      )
      expect(got.map { |edit| edit["start_byte"] }).to eq(expected.map(&:start_byte))
    end

    it "keeps the first limit candidates in order and records the rest as skipped with digests" do
      full = oracle_candidates.map(&:first)
      subject = oracle_subject
      digests = full.map { |m| m.digest(subject_start: subject.start_byte, original_source: subject.file_source) }
      limit = full.size - 1
      run_preview(config(max_mutants_per_method: limit), format: "json")
      expect(payload["mutants"].map { |e| e["digest"] }).to eq(digests.first(limit))
      expect(payload["skipped"].map { |e| e["digest"] }).to eq([digests.last])
      expect(payload["skipped"].first["reason"]).to eq("max_mutants_per_method")
      expect(payload["totals"]).to eq("mutants" => limit, "dropped_by_max_mutants_per_method" => 1,
                                      "incomplete_files" => 0)
    end

    it "does not skip or drop anything when the cap equals the candidate count" do
      full = oracle_candidates.size
      run_preview(config(max_mutants_per_method: full), format: "json")
      expect(payload["skipped"]).to eq([])
      expect(payload["totals"]["dropped_by_max_mutants_per_method"]).to eq(0)
      expect(payload["totals"]["mutants"]).to eq(full)
    end

    it "lists inline suppressions with every field and the inline_suppression reason prefix" do
      File.write(target.file,
                 "class PreviewCases\n  def m(x)\n    x + 1 # saboteur:disable-line reason=\"stop\"\n  end\nend\n")
      diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
      oracle_candidates(diagnostics: diagnostics)
      expected = diagnostics.inline_suppressions.map do |entry|
        { "digest" => entry[:digest], "subject" => entry[:subject], "operator" => entry[:operator].to_s,
          "file" => base, "line" => entry[:line], "reason" => "inline_suppression: #{entry[:reason]}" }
      end
      expect(expected).not_to be_empty
      run_preview(format: "json")
      expect(payload["skipped"]).to eq(expected)
    end

    it "lists only hazard-guard refusals, each with subject, operator, file and no digest" do
      File.write(target.file, "class PreviewCases\n  def m\n    FileUtils.rm_rf(\"tmp\")\n  end\nend\n")
      diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
      oracle_candidates(diagnostics: diagnostics)
      events = diagnostics.generation_events.select { |event| event.source == "hazard_guard" }
      expect(events).not_to be_empty
      run_preview(format: "json")
      hazards = payload["skipped"].select { |entry| entry["reason"] == "hazardous" }
      expect(payload["skipped"].size).to eq(events.size)
      expect(hazards).to eq(events.map do |event|
        { "subject" => event.subject, "operator" => event.operator.to_s, "file" => base, "reason" => "hazardous" }
      end)
    end

    it "reports discovery warnings in the payload" do
      File.write(target.file, "def broken(")
      run_preview(format: "json")
      expect(payload["warnings"]).not_to be_empty
      expect(payload["warnings"].join).to include("does not parse")
    end

    it "rounds the cached estimate to two places and omits it without a usable map" do
      settings = config(operators: ["arithmetic"])
      run_preview(settings, format: "json")
      expect(payload["estimated_seconds"]).to be_nil
      receipt(settings, { "t1" => 0.123456 })
      run_preview(settings, format: "json")
      expect(payload["totals"]["mutants"]).to eq(2)
      expect(payload["estimated_seconds"]).to eq(0.25)
      receipt(settings, {})
      run_preview(settings, format: "json")
      expect(payload["estimated_seconds"]).to be_nil
    end

    it "gives no estimate when discovery was incomplete even with a valid map" do
      settings = config(operators: ["arithmetic"])
      receipt(settings, { "t1" => 0.5 })
      File.write(target.file, "def broken(")
      run_preview(settings, format: "json")
      expect(payload["totals"]["incomplete_files"]).to eq(1)
      expect(payload["estimated_seconds"]).to be_nil
    end
  end
end
