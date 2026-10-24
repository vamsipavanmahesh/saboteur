#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "csv"
require "digest"
require "pathname"

ROOT = Pathname.new(File.expand_path("..", __dir__))
SEED = 20_261_023
GENERATED_NOTE = "Generated from the evidence files by script/summarize.rb. " \
                 "Missing measurements remain unknown. No conclusion extends beyond the measured stages."
SELECTION_RULE = "Sort unique scenario/id pairs, then Ruby Array#shuffle with Random.new(seed); " \
                 "first cap. PR-kind reports only."
CSV_BASE_COLUMNS = %w[scenario mutant_id file_line evidence_path].freeze
TRIAGE_VALUES = ["real gap", "equivalent mutant", "false survivor", "environment noise"].freeze
KILL_VALUES = ["assertion failure", "exception", "DB/infrastructure error", "timeout"].freeze

def read_json(path)
  path.file? ? JSON.parse(path.read) : nil
end

def cell(value)
  return "unknown" if value.nil?

  value.to_s.gsub("|", '\\|').gsub("\n", " ")
end

def table(headers, rows)
  ([headers, headers.map { "---" }] + rows).map { |r| "| #{r.map { |v| cell(v) }.join(' | ')} |" }.join("\n")
end

def csv_field(category)
  category == :triage ? "classification" : "cause"
end

def csv_allowed_values(category)
  category == :triage ? TRIAGE_VALUES : KILL_VALUES
end

def check_csv_row!(row, path, seen, runs, category)
  field = csv_field(category)
  key = row.values_at("scenario", "mutant_id")
  abort "Duplicate CSV scenario/id in #{path}: #{key}" if seen[key]
  seen[key] = true
  abort "Unknown #{field} in #{path}: #{row[field]}" unless csv_allowed_values(category).include?(row[field])
  abort "Missing CSV evidence reference in #{path}" if row["evidence_path"].to_s.strip.empty?
  run = runs.find { |name, measurement, _| name == key[0] && measurement["kind"] == "pr" }
  mutant = run && mutants(run[2])&.find { |m| m["id"] == key[1] }
  expected = category == :triage ? "Survived" : "Killed"
  return if mutant && mutant["status"] == expected

  abort "CSV row has no matching #{expected} PR mutant in #{path}: #{key}"
end

def csv_rows(path, runs, category)
  return nil unless path.file?

  csv = CSV.read(path, headers: true)
  field = csv_field(category)
  required = CSV_BASE_COLUMNS + [field]
  abort "Missing CSV columns in #{path}" unless (required - Array(csv.headers)).empty?
  seen = {}
  csv.map(&:to_h).each do |row|
    check_csv_row!(row, path, seen, runs, category)
  end
end

def mutants(report)
  return nil unless report

  result = report.fetch("files").flat_map do |file, entry|
    entry.fetch("mutants").map { |m| m.merge("file" => file) }
  end
  seen = {}
  result.each do |m|
    id = m.fetch("id")
    abort "Invalid mutant id: #{id.inspect}" unless id.is_a?(String) && !id.empty?
    abort "Duplicate mutant id in report: #{id}" if seen[id]
    seen[id] = true
    m.fetch("status")
  end
  result
end

def test_names(report)
  seen = {}
  report.fetch("testFiles", {}).values.flat_map { |f| f.fetch("tests", []) }.each do |t|
    id = t.fetch("id")
    abort "Duplicate test id in report: #{id}" if seen.key?(id)
    seen[id] = t.fetch("name")
  end
  seen
end

def verdicts(report)
  tests = test_names(report)
  rows = mutants(report).map do |m|
    # Include stable identity and semantic verdict fields. Runtime and test-table
    # allocation IDs are deliberately excluded; test references become names.
    [m.fetch("id"), m["file"], m["location"], m["subject"], m["mutatorName"], m["replacement"],
     m.fetch("status"), Array(m["killedBy"]).map { |id| tests.fetch(id) }.sort,
     m["gap"], m["gapKind"], m["kind"], m["classification"], m["valueDiffered"],
     m["confirmation"], m["rejectedKill"], m["statusReason"],
     m["creditedTest"] && tests.fetch(m["creditedTest"])]
  end
  rows.sort_by(&:first)
end

def load_runs(app)
  app.join("reports").glob("*/measurement.json").sort.map do |path|
    [path.parent.basename.to_s, read_json(path), read_json(path.parent.join("report.json"))]
  end
end

def baseline_run(runs)
  runs.find { |name, m, _| name == "baseline" && m["kind"] == "baseline" } ||
    runs.find { |_, m, _| m["kind"] == "baseline" }
end

def stage_rows(stages)
  stages.map { |name, s| [name, s["status"], s["reason"], Array(s["evidence"]).join(", ")] }
end

def run_rows(runs)
  runs.map do |name, m, _|
    [name, m["kind"], m["status"], m["saboteur_version"], m["saboteur_sha"], m["base_sha"],
     m["head_sha"], m["wall_seconds"], m["peak_rss_kb"], m["exit_code"]]
  end
end

def baseline_example_lines(app)
  baseline_json = read_json(app.join("logs/baseline-rspec.json"))
  summary = baseline_json && baseline_json["summary"]
  row = [summary && summary["example_count"], summary && summary["failure_count"],
         summary && summary["pending_count"], summary && summary["errors_outside_of_examples_count"]]
  ["", "### Baseline example results", "",
   table(["Examples", "Failures", "Pending", "Errors outside examples"], [row]), "", ""]
end

def extra_baseline_rows(app, runs)
  runs.select { |name, m, _| name != "baseline" && m["kind"] == "baseline" }.map do |name, measurement, _|
    [name] + extra_baseline_summary(app, name, measurement) + [measurement["wall_seconds"]]
  end
end

def extra_baseline_summary(app, name, measurement)
  evidence = Array(measurement["evidence_paths"]).select { |path| path.end_with?("-rspec.json") }
  paths = evidence.flat_map { |path| [ROOT.join(path), app.join(path)] }.select(&:file?).uniq
  abort "Ambiguous baseline evidence for #{app.basename}/#{name}" if paths.size > 1

  summary = paths.first && read_json(paths.first)&.fetch("summary", nil)
  [summary && summary["example_count"], summary && summary["failure_count"],
   summary && summary["pending_count"], summary && summary["errors_outside_of_examples_count"]]
end

def pr_run_rows(runs)
  runs.select { |_, m, _| m["kind"] == "pr" }.map { |name, m, report| pr_run_row(name, m, report) }
end

def status_breakdown(mutant_rows)
  counts = mutant_rows&.group_by { |v| v["status"] }&.transform_values(&:size)
  count = ->(key) { counts&.fetch(key, 0) }
  errors = counts && %w[RuntimeError CompileError].sum { |key| counts.fetch(key, 0) }
  known = counts && %w[Killed Survived Timeout RuntimeError CompileError].sum { |key| counts.fetch(key, 0) }
  [count.call("Killed"), count.call("Survived"), count.call("Timeout"), errors,
   mutant_rows && (mutant_rows.size - known)]
end

def pr_run_row(name, measurement, report)
  ms = mutants(report)
  killed, survived, timeout, errors, other = status_breakdown(ms)
  # Use the tool's own score, not an assumed mutation-score formula.
  score = report&.dig("saboteur", "scores", "all")
  [name, measurement["pr_url"], ms&.size, killed, survived, timeout, errors, other,
   score && JSON.generate(score)]
end

def count_rows(rows, field)
  return [["unknown", nil]] unless rows && !rows.empty?

  rows.group_by { |r| r.fetch(field) }.sort.map { |key, group| [key, group.size] }
end

def false_survivor_rows(triage)
  return [["unknown", nil, nil, nil]] unless triage

  triage.select { |r| r["classification"] == "false survivor" }
        .map { |r| r.values_at("scenario", "mutant_id", "file_line", "evidence_path") }
end

def comparison_row(app, runs, name, measurement, report)
  reference = runs.find { |n, _, _| n == measurement["reference_scenario"] }
  unless report && reference && reference[2]
    return [name, measurement["reference_scenario"], nil, nil, "unknown: raw report or reference missing"]
  end

  left = verdicts(reference[2])
  right = verdicts(report)
  diff = { reference: reference[0], compared: name, only_reference: left - right, only_compared: right - left }
  dir = app.join("verification")
  dir.mkpath
  dir.join("#{name}-verdict-diff.json").write("#{JSON.pretty_generate(diff)}\n")
  [name, reference[0], diff[:only_reference].size, diff[:only_compared].size,
   "apps/#{app.basename}/verification/#{name}-verdict-diff.json"]
end

def comparison_rows(app, runs)
  rows = runs.select { |_, m, _| %w[parallel determinism].include?(m["kind"]) }.map do |name, m, report|
    comparison_row(app, runs, name, m, report)
  end
  rows.empty? ? [["unknown", nil, nil, nil, nil]] : rows
end

def selection_candidates(runs)
  mapped = runs.select { |_, m, r| m["kind"] == "pr" && r }.flat_map do |name, _, report|
    mutants(report).map do |m|
      { scenario: name, id: m.fetch("id"), file: m.fetch("file"), line: m.dig("location", "start", "line"),
        status: m.fetch("status") }
    end
  end
  mapped.uniq { |m| [m[:scenario], m[:id]] }.sort_by { |m| [m[:scenario], m[:id]] }
end

def draw(candidates, status, cap)
  # shuffle/first with the seeded RNG is the published selection rule; Array#sample
  # would draw different mutants for the same seed.
  # rubocop:disable-next Style/Sample
  candidates.select { |m| m[:status] == status }.shuffle(random: Random.new(SEED)).first(cap)
end

def write_selection(app, runs)
  return unless ARGV.include?("--select") && runs.any? { |_, m, r| m["kind"] == "pr" && r }

  candidates = selection_candidates(runs)
  selected = { seed: SEED, candidates_sha256: Digest::SHA256.hexdigest(JSON.generate(candidates)),
               rule: SELECTION_RULE,
               survivors: draw(candidates, "Survived", 25), kills: draw(candidates, "Killed", 10) }
  target = app.join("verification/selected.json")
  encoded = "#{JSON.pretty_generate(selected)}\n"
  abort "Refusing to replace changed selection: #{target}" if target.file? && target.read != encoded

  target.parent.mkpath
  target.write(encoded)
end

def record_summary(summary, app, metadata, runs)
  base = baseline_run(runs)
  map = runs.find { |_, m, _| m["kind"] == "map" }
  summary << [app.basename, metadata["shape"], metadata["ruby_files"], metadata["spec_files"],
              base&.dig(1, "wall_seconds"), map&.dig(1, "wall_seconds")]
end

def app_findings(app)
  path = app.join("findings.md")
  path.file? ? path.read : "Unknown pending execution and verification."
end

def app_sections(app, summary)
  metadata = read_json(app.join("metadata.json")) || {}
  stages = read_json(app.join("stages.json")) || {}
  runs = load_runs(app)
  runs.each { |_, _, report| verdicts(report) if report }
  record_summary(summary, app, metadata, runs)
  sections = app_status_sections(app, metadata, stages, runs)
  sections += ["### Per-PR raw results", "",
               table(%w[Scenario PR Mutants Killed Survived Timeout Errors Other Score], pr_run_rows(runs))]
  sections += app_result_sections(app, runs)
  write_selection(app, runs)
  sections + ["", "### App findings", "", app_findings(app), ""]
end

def app_status_sections(app, metadata, stages, runs)
  out = ["## #{app.basename}", "",
         "Source: #{cell(metadata['repository'])} at `#{cell(metadata['sha'])}`.", "",
         "### Stage status", "", table(%w[Stage Status Reason Evidence], stage_rows(stages)), "",
         "### Runs and resource cost", "",
         table(["Scenario", "Kind", "Status", "Version", "Saboteur SHA", "Base", "Head", "Wall (s)",
                "Peak RSS (KiB)", "Exit"], run_rows(runs))]
  out += baseline_example_lines(app)
  extra = extra_baseline_rows(app, runs)
  unless extra.empty?
    out += ["### Additional baseline results", "",
            table(["Scenario", "Examples", "Failures", "Pending", "Errors outside examples", "Wall (s)"], extra), ""]
  end
  out
end

def app_result_sections(app, runs)
  triage = csv_rows(app.join("triage.csv"), runs, :triage)
  kills = csv_rows(app.join("kills.csv"), runs, :kills)
  fake_kills = kills && !kills.empty? ? kills.count { |r| r["cause"] == "DB/infrastructure error" } : nil
  ["", "### Survivor triage counts", "", table(%w[Classification Count], count_rows(triage, "classification")),
   "", "### Kill causes", "", table(%w[Cause Count], count_rows(kills, "cause")),
   "", "Fake kills: #{cell(fake_kills)}.", "",
   "### False survivors", "",
   table(%w[Scenario ID Location Evidence], false_survivor_rows(triage)), "",
   "### Parallel and determinism verdict comparisons", "",
   table(["Scenario", "Reference", "Reference-only rows", "Compared-only rows", "Diff evidence"],
         comparison_rows(app, runs))]
end

out = ["# Saboteur Rails field report", "", GENERATED_NOTE, ""]
summary = []
apps = ROOT.join("apps").children.select(&:directory?).sort
apps.each { |app| out += app_sections(app, summary) }
out.insert(4, "## App summary", "",
           table(["App", "Shape", "Tracked Ruby files", "Tracked spec files", "Baseline (s)", "Map (s)"], summary), "")
out += ["", ROOT.join("findings.md").read]
ROOT.join("REPORT.md").write("#{out.join("\n")}\n")
puts "Generated REPORT.md"
