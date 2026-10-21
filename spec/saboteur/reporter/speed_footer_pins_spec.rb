# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Golden pins for PR16's speed footer: the run's wall time split into
# baseline / map / mutants plus the worker count, and a "slowest:" line for
# an outlier mutant. A diagnostic: hidden on a fast default run, always on
# at --verbose, on by default when an overhead phase exceeds its share.
RSpec.describe Saboteur::Reporter::Terminal, "speed footer pins" do
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

  def invoice_subject
    @invoice_subject ||= subjects_in("class Invoice\n  def recalculate; @total * 1; end\nend\n",
                                     name: "invoice.rb").first
  end

  def timed_result(runtime, operator: "literal_number", subject: invoice_subject)
    at = subject.file_source.index("1")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1,
                                              replacement: "2")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator:, edits: [edit],
                                                      coarse: false)
    Saboteur::MutantResult.new(subject:, mutation:, status: :killed,
                               mutated_source: subject.apply([edit]), runtime:)
  end

  def timings(baseline: 8.2, map: 2.1, cached: false, mutants: 41.0, jobs: 4)
    Saboteur::PhaseTimings.new(baseline_seconds: baseline, map_seconds: map, map_cached: cached,
                               mutants_seconds: mutants, jobs:)
  end

  def footer_report(*results, wall: 51.3, phase_timings: timings)
    Saboteur::Report.new(results:, subjects: [invoice_subject], wall_time: wall,
                         root: File.dirname(invoice_subject.file), seed: 1, phase_timings:)
  end

  let(:options) { { exit_code: 0, scope: "whole project", verbose: true } }
  let(:outlier_results) { [timed_result(0.4), timed_result(0.4), timed_result(3.4)] }

  it "prints the golden footer and slowest line in monochrome" do
    expect(render(footer_report(*outlier_results), **options)).to include(<<~TEXT)
      speed footer: done in 51.3s - baseline 8.2s · map 2.1s · mutants 41.0s (jobs=4)
        slowest: Invoice#recalculate (literal_number, 3.4s)
    TEXT
  end

  it "prints the golden footer and slowest line under colour, all dim" do
    text = render(footer_report(*outlier_results), **options, color: :always)
    expect(text).to include(
      "\e[2mspeed footer: done in 51.3s - baseline 8.2s \u00B7 map 2.1s \u00B7 mutants 41.0s (jobs=4)\e[0m\n" \
      "\e[2m  slowest: Invoice#recalculate (literal_number, 3.4s)\e[0m\n"
    )
  end

  it "stays hidden on a fast default run" do
    fast = timings(baseline: 1.0, map: 0.5, mutants: 10.0)
    text = render(footer_report(timed_result(0.4), wall: 12.0, phase_timings: fast),
                  **options, verbose: false)
    expect(text).not_to include("speed footer")
  end

  it "shows by default when the baseline phase exceeds its budget share" do
    slow_baseline = timings(baseline: 8.2, map: 2.1, mutants: 19.7)
    text = render(footer_report(timed_result(0.4), wall: 30.0, phase_timings: slow_baseline),
                  **options, verbose: false)
    expect(text).to include("speed footer: done in 30.0s - baseline 8.2s")
  end

  it "shows by default when the map phase exceeds its budget share" do
    slow_map = timings(baseline: 1.0, map: 14.0, mutants: 38.0)
    text = render(footer_report(timed_result(0.4), wall: 53.0, phase_timings: slow_map),
                  **options, verbose: false)
    expect(text).to include("map 14.0s")
  end

  it "pins the share boundary: exactly a quarter of the wall is not an excess" do
    boundary = timings(baseline: 8.2, map: 2.1, mutants: 22.5)
    text = render(footer_report(timed_result(0.4), wall: 32.8, phase_timings: boundary),
                  **options, verbose: false)
    expect(text).not_to include("speed footer")
  end

  it "pins the floor boundary: a 2.0s overhead phase never nags however large its share" do
    tiny = timings(baseline: 2.0, map: 0.5, mutants: 1.5)
    text = render(footer_report(timed_result(0.4), wall: 4.0, phase_timings: tiny),
                  **options, verbose: false)
    expect(text).not_to include("speed footer")
  end

  it "reports a cached map as 0.0s (cached), never the reused build's cost" do
    cached = timings(cached: true, map: 9.9)
    expect(cached.map_seconds).to eq(0.0)
    text = render(footer_report(timed_result(0.4), phase_timings: cached), **options)
    expect(text).to include("map 0.0s (cached)")
  end

  it "keeps the three phase durations inside the wall time (no double counting)" do
    canned = timings(baseline: 8.2, map: 2.1, mutants: 41.0)
    expect(canned.baseline_seconds + canned.map_seconds + canned.mutants_seconds).to be <= 51.3
  end

  it "names the run's worker count" do
    expect(render(footer_report(timed_result(0.4)), **options)).to include("(jobs=4)")
    serial = timings(jobs: 1)
    expect(render(footer_report(timed_result(0.4), phase_timings: serial), **options)).to include("(jobs=1)")
  end

  it "prints no footer without phase timings (--test-command runs), even at --verbose" do
    report = footer_report(timed_result(0.4), phase_timings: nil)
    expect(render(report, **options)).not_to include("speed footer")
  end

  it "never names a slowest mutant when durations are uniform" do
    uniform = [timed_result(0.4), timed_result(0.4), timed_result(0.4)]
    expect(render(footer_report(*uniform), **options)).not_to include("slowest:")
  end

  it "pins the outlier factor boundary: exactly 5x the median is not an outlier" do
    boundary = [timed_result(2.0), timed_result(2.0), timed_result(10.0)]
    expect(render(footer_report(*boundary), **options)).not_to include("slowest:")
  end

  it "names the mutant just past the outlier factor boundary" do
    past = [timed_result(2.0), timed_result(2.0), timed_result(10.1)]
    expect(render(footer_report(*past), **options))
      .to include("  slowest: Invoice#recalculate (literal_number, 10.1s)")
  end

  it "pins the outlier floor boundary: exactly 1.0s is never an outlier" do
    floor = [timed_result(0.1), timed_result(0.1), timed_result(1.0)]
    expect(render(footer_report(*floor), **options)).not_to include("slowest:")
  end

  it "names a mutant just past the 1.0s floor" do
    past_floor = [timed_result(0.1), timed_result(0.1), timed_result(1.1)]
    expect(render(footer_report(*past_floor), **options)).to include("slowest: Invoice#recalculate")
  end

  it "names nothing for a single-mutant run (it is its own median)" do
    expect(render(footer_report(timed_result(5.0)), **options)).not_to include("slowest:")
  end
end
