# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Golden pins for PR6's clean-run success screen: a fully-killed run says
# the win out loud (the ruff#8553 lesson).
RSpec.describe Saboteur::Reporter::Terminal, "clean screen pins" do
  # The goldens carry UTF-8 glyphs; pin the locale so C-locale CI keeps them.
  around do |example|
    saved = ENV.to_h.slice("LC_ALL", "LC_CTYPE", "LANG")
    ENV["LC_ALL"] = "C.UTF-8"
    example.run
  ensure
    keys = %w[LC_ALL LC_CTYPE LANG]
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
  end

  def render(report, **options)
    io = StringIO.new
    described_class.new(io, **options).call(report)
    io.string
  end

  def killed_result
    result_for(:killed)
  end

  def clean_report(*results, **extra)
    Saboteur::Report.new(results: results, subjects: [person_subject], wall_time: 2.3,
                         root: File.dirname(person_subject.file), seed: 1, **extra)
  end

  let(:report) { clean_report(killed_result, killed_result) }
  let(:options) { { exit_code: 0, scope: "whole project", html_report: ".saboteur/report.html" } }

  it "prints the golden success screen in monochrome" do
    expect(render(report, **options)).to eq(<<~TEXT)
      saboteur #{Saboteur::VERSION} · whole project · seed 1

      ✓ 2/2 mutants killed · score 100.0% · 2.3s total
        reports: .saboteur/report.html · next: saboteur run --since origin/main
    TEXT
  end

  it "prints the golden success screen under colour" do
    expect(render(report, **options, color: :always)).to eq(<<~TEXT)
      \e[2msaboteur #{Saboteur::VERSION} · whole project · seed 1\e[0m

      \e[32m✓ 2/2 mutants killed · score 100.0%\e[0m \e[2m· 2.3s total\e[0m
        \e[2mreports: .saboteur/report.html · next: saboteur run --since origin/main\e[0m
    TEXT
  end

  it "keeps the win and appends the warn line when subjects are untested at 100%" do
    other = subjects_in("class Other\n  def m; 1; end\nend\n", name: "other.rb").first
    text = render(clean_report(killed_result, skipped_subjects: { other => "no coverage" }), **options)
    expect(text).to include("✓ 1/1 mutants killed · score 100.0% · 2.3s total\n",
                            "  1 subject not scored - no tests exist: #{other.id}\n")
  end

  it "names every untested subject in the warn line" do
    others = subjects_in("class A\n  def m; 1; end\nend\nclass B\n  def n; 2; end\nend\n", name: "ab.rb")
    text = render(clean_report(killed_result,
                               skipped_subjects: others.to_h { |subject| [subject, "no coverage"] }), **options)
    ids = others.sort_by { |subject| [subject.file, subject.start_line] }.map(&:id)
    expect(text).to include("  2 subjects not scored - no tests exist: #{ids.join(', ')}\n")
  end

  it "names the diff scope and drops the whole-project next hint" do
    text = render(clean_report(killed_result), **options, scope: "--since origin/main")
    expect(text).to include("saboteur #{Saboteur::VERSION} · --since origin/main · seed 1\n")
    expect(text).to include("  reports: .saboteur/report.html\n")
    expect(text).not_to include("next:")
  end

  it "keeps the incremental reuse note from the JSON report on a clean run (#1138)" do
    text = render(clean_report(killed_result, result_for(:killed, reused: true)), **options)
    expect(text).to include("  reused 1 of 2 verdicts from earlier runs (--incremental)\n")
  end

  it "keeps the hazard-suppression note from the JSON report on a clean run (#1138)" do
    text = render(clean_report(killed_result, hazard_suppressions: 3), **options)
    expect(text).to include("  hazardous mutations suppressed: 3 " \
                            "(--allow-hazardous runs them anyway; the canary still watches the tree)\n")
  end

  it "omits both notes when nothing was reused or suppressed" do
    text = render(report, **options)
    expect(text).not_to include("reused", "hazardous mutations suppressed")
  end

  it "yields to the baseline tail on a gated clean run (PR8 owns that screen)" do
    categories = %w[accepted changed resolved_kills detected_timeouts new unmatched errors].to_h { |k| [k, []] }
    comparison = instance_double(Saboteur::Baseline::Comparison, categories:, score: nil)
    gate = instance_double(Saboteur::Baseline::RunGate, comparison:, new_survivor_ids: [])
    text = render(report, **options, baseline_gate: gate)
    expect(text).to include("saboteur: 0 mutants matched the baseline, no new survivors\n")
    expect(text).not_to include("mutants killed · score")
  end

  it "keeps the ordinary closing block when nothing was tested" do
    text = render(clean_report, **options)
    expect(text).to include("saboteur: no mutants in 2s - score n/a\n")
    expect(text).not_to include("mutants killed · score")
  end

  it "keeps the ordinary closing block when any mutant errored, timed out or was unverified" do
    [%i[error], %i[timeout], %i[unverified], %i[resource_limit], %i[error timeout],
     %i[timeout unverified], %i[unverified resource_limit]].each do |statuses|
      text = render(clean_report(*statuses.map { |status| result_for(status) }), **options)
      expect(text).not_to include("mutants killed · score")
    end
  end

  it "keeps the ordinary closing block when survivors exist, even at exit 0" do
    text = render(clean_report(killed_result, result_for(:survived)), **options)
    expect(text).not_to include("mutants killed · score")
  end

  it "keeps the ordinary closing block when the run stopped early" do
    stop = Saboteur::EarlyStop.new(reason: "fail_fast", unreached: [], truncated: [], unverified: [])
    text = render(clean_report(killed_result, early_stop: stop), **options)
    expect(text).not_to include("mutants killed · score")
  end

  it "omits the seed clause when the run recorded no seed" do
    report = Saboteur::Report.new(results: [killed_result], subjects: [person_subject], wall_time: 2.3,
                                  root: File.dirname(person_subject.file))
    expect(render(report, **options)).to include("saboteur #{Saboteur::VERSION} · whole project
")
  end

  it "shows the real score when an ignored survivor keeps the run clean" do
    ignored = result_for(:survived)
    ignored.ignored = "equivalent: hand-probed"
    text = render(clean_report(killed_result, ignored), **options)
    expect(text).to include("✓ 1/2 mutants killed · score 50.0% · 2.3s total
")
  end

  it "renders the baseline, coverage and dots lines only when phase data is present" do
    with_phases = render(report, **options, baseline: { examples: 6, seconds: 0.3 },
                                            coverage: { tests: 6, seconds: 0.2 }, mutant_phase: { seconds: 1.8 })
    expect(with_phases).to include("✓ baseline green (6 examples, 0.3s)  ✓ coverage map: 6 tests (0.2s)\n")
    expect(with_phases).to include("..  (2/2 · 1.8s)
")
    expect(render(report, **options)).not_to include("baseline green", "coverage map:")
  end

  it "skips the phase lines when only some phase data is present" do
    baseline = { examples: 6, seconds: 0.3 }
    coverage = { tests: 6, seconds: 0.2 }
    mutant_phase = { seconds: 1.8 }
    [
      [{ baseline:, coverage: }, "baseline green"],
      [{ baseline:, mutant_phase: }, "baseline green"],
      [{ coverage:, mutant_phase: }, "coverage map:"],
      [{ mutant_phase: }, "(2/2 · 1.8s)"]
    ].each do |phases, marker|
      expect(render(report, **options, **phases)).not_to include(marker)
    end
  end

  it "keeps the ordinary closing block when the run is not clean" do
    dirty = clean_report(killed_result, result_for(:survived))
    text = render(dirty, **options, exit_code: 1)
    expect(text).to include("Survivors (1) - changes your tests did not catch", "saboteur: 1 killed, 1 survived")
    expect(text).not_to include("mutants killed · score")
  end
end
