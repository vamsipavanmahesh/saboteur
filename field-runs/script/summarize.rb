#!/usr/bin/env ruby
# frozen_string_literal: true
require 'json'
require 'csv'
require 'digest'
require 'pathname'

ROOT = Pathname.new(File.expand_path('..', __dir__))
SEED = 20261023

def read_json(path)
  path.file? ? JSON.parse(path.read) : nil
end

def cell(value)
  return 'unknown' if value.nil?
  value.to_s.gsub('|', '\\|').gsub("\n", ' ')
end

def table(headers, rows)
  ([headers, headers.map { '---' }] + rows).map { |r| '| ' + r.map { |v| cell(v) }.join(' | ') + ' |' }.join("\n")
end

def csv_rows(path, runs, category)
  return nil unless path.file?
  csv = CSV.read(path, headers: true)
  field = category == :triage ? 'classification' : 'cause'
  required = %w[scenario mutant_id file_line evidence_path] + [field]
  abort "Missing CSV columns in #{path}" unless (required - Array(csv.headers)).empty?
  allowed = category == :triage ? ['real gap', 'equivalent mutant', 'false survivor', 'environment noise'] : ['assertion failure', 'exception', 'DB/infrastructure error', 'timeout']
  seen = {}
  csv.map(&:to_h).each do |row|
    key = row.values_at('scenario', 'mutant_id')
    abort "Duplicate CSV scenario/id in #{path}: #{key}" if seen[key]
    seen[key] = true
    abort "Unknown #{field} in #{path}: #{row[field]}" unless allowed.include?(row[field])
    abort "Missing CSV evidence reference in #{path}" if row['evidence_path'].to_s.strip.empty?
    run = runs.find { |name, measurement, _| name == key[0] && measurement['kind'] == 'pr' }
    mutant = run && mutants(run[2])&.find { |m| m['id'] == key[1] }
    expected = category == :triage ? 'Survived' : 'Killed'
    abort "CSV row has no matching #{expected} PR mutant in #{path}: #{key}" unless mutant && mutant['status'] == expected
  end
end

def mutants(report)
  return nil unless report
  result = report.fetch('files').flat_map do |file, entry|
    entry.fetch('mutants').map { |m| m.merge('file' => file) }
  end
  seen = {}
  result.each do |m|
    id = m.fetch('id')
    abort "Invalid mutant id: #{id.inspect}" unless id.is_a?(String) && !id.empty?
    abort "Duplicate mutant id in report: #{id}" if seen[id]
    seen[id] = true
    m.fetch('status')
  end
  result
end

def test_names(report)
  seen = {}
  report.fetch('testFiles', {}).values.flat_map { |f| f.fetch('tests', []) }.each do |t|
    id = t.fetch('id')
    abort "Duplicate test id in report: #{id}" if seen.key?(id)
    seen[id] = t.fetch('name')
  end
  seen
end

def verdicts(report)
  tests = test_names(report)
  mutants(report).map do |m|
    # Include stable identity and semantic verdict fields. Runtime and test-table
    # allocation IDs are deliberately excluded; test references become names.
    [m.fetch('id'), m['file'], m['location'], m['subject'], m['mutatorName'], m['replacement'],
     m.fetch('status'), Array(m['killedBy']).map { |id| tests.fetch(id) }.sort,
     m['gap'], m['gapKind'], m['kind'], m['classification'], m['valueDiffered'],
     m['confirmation'], m['rejectedKill'], m['statusReason'],
     m['creditedTest'] && tests.fetch(m['creditedTest'])]
  end.sort_by { |v| v.first }
end

out = ['# Saboteur Rails field report', '', 'Generated from the evidence files by script/summarize.rb. Missing measurements remain unknown. No conclusion extends beyond the measured stages.', '']
summary = []
apps = ROOT.join('apps').children.select(&:directory?).sort
apps.each do |app|
  metadata = read_json(app.join('metadata.json')) || {}
  stages = read_json(app.join('stages.json')) || {}
  runs = app.join('reports').glob('*/measurement.json').sort.map do |path|
    [path.parent.basename.to_s, read_json(path), read_json(path.parent.join('report.json'))]
  end
  runs.each { |_, _, report| verdicts(report) if report }
  base = runs.find { |name, m, _| name == 'baseline' && m['kind'] == 'baseline' } || runs.find { |_, m, _| m['kind'] == 'baseline' }
  map = runs.find { |_, m, _| m['kind'] == 'map' }
  summary << [app.basename, metadata['shape'], metadata['ruby_files'], metadata['spec_files'], base&.dig(1, 'wall_seconds'), map&.dig(1, 'wall_seconds')]
  out += ["## #{app.basename}", '', "Source: #{cell(metadata['repository'])} at `#{cell(metadata['sha'])}`.", '', '### Stage status', '', table(%w[Stage Status Reason Evidence], stages.map { |name, s| [name, s['status'], s['reason'], Array(s['evidence']).join(', ')] }), '', '### Runs and resource cost', '']
  out << table(['Scenario', 'Kind', 'Status', 'Version', 'Saboteur SHA', 'Base', 'Head', 'Wall (s)', 'Peak RSS (KiB)', 'Exit'], runs.map { |name, m, _| [name, m['kind'], m['status'], m['saboteur_version'], m['saboteur_sha'], m['base_sha'], m['head_sha'], m['wall_seconds'], m['peak_rss_kb'], m['exit_code']] })
  baseline_json = read_json(app.join('logs/baseline-rspec.json'))
  baseline_summary = baseline_json && baseline_json['summary']
  out += ['', '### Baseline example results', '', table(['Examples', 'Failures', 'Pending', 'Errors outside examples'], [[baseline_summary && baseline_summary['example_count'], baseline_summary && baseline_summary['failure_count'], baseline_summary && baseline_summary['pending_count'], baseline_summary && baseline_summary['errors_outside_of_examples_count']]]), '', '']
  extra_baselines = runs.select { |name, m, _| name != 'baseline' && m['kind'] == 'baseline' }.map do |name, measurement, _|
    evidence = Array(measurement['evidence_paths']).select { |path| path.end_with?('-rspec.json') }
    paths = evidence.flat_map { |path| [ROOT.join(path), app.join(path)] }.select(&:file?).uniq
    abort "Ambiguous baseline evidence for #{app.basename}/#{name}" if paths.size > 1
    extra_summary = paths.first && read_json(paths.first)&.fetch('summary', nil)
    [name, extra_summary && extra_summary['example_count'], extra_summary && extra_summary['failure_count'], extra_summary && extra_summary['pending_count'], extra_summary && extra_summary['errors_outside_of_examples_count'], measurement['wall_seconds']]
  end
  unless extra_baselines.empty?
    out += ['### Additional baseline results', '', table(['Scenario', 'Examples', 'Failures', 'Pending', 'Errors outside examples', 'Wall (s)'], extra_baselines), '']
  end
  out += ['### Per-PR raw results', '']
  out << table(['Scenario', 'PR', 'Mutants', 'Killed', 'Survived', 'Timeout', 'Errors', 'Other', 'Score'], runs.select { |_, m, _| m['kind'] == 'pr' }.map do |name, m, report|
    ms = mutants(report)
    counts = ms&.group_by { |v| v['status'] }&.transform_values(&:size)
    count = ->(key) { counts ? counts.fetch(key, 0) : nil }
    errors = counts && %w[RuntimeError CompileError].sum { |key| counts.fetch(key, 0) }
    known = counts && %w[Killed Survived Timeout RuntimeError CompileError].sum { |key| counts.fetch(key, 0) }
    # Use the tool's own score, not an assumed mutation-score formula.
    score = report&.dig('saboteur', 'scores', 'all')
    [name, m['pr_url'], ms&.size, count.call('Killed'), count.call('Survived'), count.call('Timeout'), errors, ms && ms.size - known, score && JSON.generate(score)]
  end)
  triage = csv_rows(app.join('triage.csv'), runs, :triage)
  kills = csv_rows(app.join('kills.csv'), runs, :kills)
  out += ['', '### Survivor triage counts', '', table(%w[Classification Count], triage && !triage.empty? ? triage.group_by { |r| r.fetch('classification') }.sort.map { |k, v| [k, v.size] } : [['unknown', nil]]), '', '### Kill causes', '', table(%w[Cause Count], kills && !kills.empty? ? kills.group_by { |r| r.fetch('cause') }.sort.map { |k, v| [k, v.size] } : [['unknown', nil]])]
  out += ['', "Fake kills: #{cell(kills && !kills.empty? ? kills.count { |r| r['cause'] == 'DB/infrastructure error' } : nil)}.", '', '### False survivors', '', table(%w[Scenario ID Location Evidence], triage ? triage.select { |r| r['classification'] == 'false survivor' }.map { |r| r.values_at('scenario', 'mutant_id', 'file_line', 'evidence_path') } : [['unknown', nil, nil, nil]]), '', '### Parallel and determinism verdict comparisons', '']
  comparisons = runs.select { |_, m, _| %w[parallel determinism].include?(m['kind']) }.map do |name, m, report|
    reference = runs.find { |n, _, _| n == m['reference_scenario'] }
    if report && reference && reference[2]
      left = verdicts(reference[2]); right = verdicts(report)
      diff = { reference: reference[0], compared: name, only_reference: left - right, only_compared: right - left }
      dir = app.join('verification'); dir.mkpath
      dir.join("#{name}-verdict-diff.json").write(JSON.pretty_generate(diff) + "\n")
      [name, reference[0], diff[:only_reference].size, diff[:only_compared].size, "apps/#{app.basename}/verification/#{name}-verdict-diff.json"]
    else
      [name, m['reference_scenario'], nil, nil, 'unknown: raw report or reference missing']
    end
  end
  out << table(['Scenario', 'Reference', 'Reference-only rows', 'Compared-only rows', 'Diff evidence'], comparisons.empty? ? [['unknown', nil, nil, nil, nil]] : comparisons)
  if ARGV.include?('--select') && runs.any? { |_, m, r| m['kind'] == 'pr' && r }
    candidates = runs.select { |_, m, r| m['kind'] == 'pr' && r }.flat_map do |name, _, report|
      mutants(report).map { |m| { scenario: name, id: m.fetch('id'), file: m.fetch('file'), line: m.dig('location', 'start', 'line'), status: m.fetch('status') } }
    end.uniq { |m| [m[:scenario], m[:id]] }.sort_by { |m| [m[:scenario], m[:id]] }
    selected = { seed: SEED, candidates_sha256: Digest::SHA256.hexdigest(JSON.generate(candidates)), rule: 'Sort unique scenario/id pairs, then Ruby Array#shuffle with Random.new(seed); first cap. PR-kind reports only.', survivors: candidates.select { |m| m[:status] == 'Survived' }.shuffle(random: Random.new(SEED)).first(25), kills: candidates.select { |m| m[:status] == 'Killed' }.shuffle(random: Random.new(SEED)).first(10) }
    target = app.join('verification/selected.json')
    encoded = JSON.pretty_generate(selected) + "\n"
    abort "Refusing to replace changed selection: #{target}" if target.file? && target.read != encoded
    target.parent.mkpath
    target.write(encoded)
  end
  out += ['', '### App findings', '', app.join('findings.md').file? ? app.join('findings.md').read : 'Unknown pending execution and verification.', '']
end
out.insert(4, '## App summary', '', table(['App', 'Shape', 'Tracked Ruby files', 'Tracked spec files', 'Baseline (s)', 'Map (s)'], summary), '')
out += ['', ROOT.join('findings.md').read]
ROOT.join('REPORT.md').write(out.join("\n") + "\n")
puts 'Generated REPORT.md'
