# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::Terminal, "list caps" do
  let(:out) { StringIO.new }

  def render(report)
    described_class.new(out).call(report)
    out.string
  end

  def matrix_report(*results)
    Saboteur::Report.new(results: results, subjects: [person_subject], wall_time: 1.0,
                         root: File.dirname(person_subject.file), seed: 1, matrix: true)
  end

  def errors(count)
    Array.new(count) { |index| result_for(:error, reason: "boom #{index}", replacement: "r#{index}") }
  end

  def stopped_report(unreached)
    stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: unreached, truncated: [], unverified: [])
    Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                         root: File.dirname(person_subject.file), seed: 1, early_stop: stop)
  end

  it "prints no more-line for exactly 20 blind tests, and one for 21" do
    names = Array.new(21) { |index| "t#{format('%02d', index)}" }
    twenty = render(matrix_report(result_for(:survived, covered_by: names.first(20), executed: names.first(20))))
    expect(twenty).to include("blind (covered mutants, killed none): 20\n    t00  1 covered\n")
    expect(twenty[twenty.index("test matrix")..]).not_to match(/\.\.\. \d+ more/)
    out.truncate(0)
    out.rewind
    expect(render(matrix_report(result_for(:survived, covered_by: names, executed: names))))
      .to include("    t19  1 covered\n    ... 1 more\n")
  end

  it "prints the matrix without an incomplete note when every covering test ran" do
    whole = result_for(:killed, killed_by: %w[a], covered_by: %w[a], executed: %w[a])
    text = render(matrix_report(whole))
    expect(text).to include("test matrix: 1 tests ran against mutants\n  blind")
    expect(text).not_to include("incomplete")
  end

  it "prints no more-line for exactly 10 errors, and one for 11" do
    ten = render(Saboteur::Report.new(results: errors(10), subjects: [person_subject], wall_time: 1.0,
                                      root: File.dirname(person_subject.file), seed: 1))
    expect(ten).to include("boom 9")
    expect(ten).not_to include("... ")
    out.truncate(0)
    out.rewind
    eleven = render(Saboteur::Report.new(results: errors(11), subjects: [person_subject], wall_time: 1.0,
                                         root: File.dirname(person_subject.file), seed: 1))
    expect(eleven).to include("boom 9").and include("  ... 1 more\n")
    expect(eleven).not_to include("boom 10")
  end

  it "prints no more-line for exactly 10 unreached subjects, and one for 11" do
    ids = Array.new(11) { |index| "S#{index}#m" }
    ten = render(stopped_report(ids.first(10)))
    expect(ten).to include("  not run: S9#m\n")
    expect(ten).not_to include("... ")
    out.truncate(0)
    out.rewind
    eleven = render(stopped_report(ids))
    expect(eleven).to include("  not run: S9#m\n  ... 1 more\n")
    expect(eleven).not_to include("S10#m")
  end
end
