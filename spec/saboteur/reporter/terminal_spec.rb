# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::Terminal do
  let(:out) { StringIO.new }

  def render(report)
    described_class.new(out).call(report)
    out.string
  end

  it "prints counts, score, timing and a diff per survivor" do
    text = render(report_of(result_for(:killed, runtime: 0.5), result_for(:survived, runtime: 0.5)))
    expect(text).to include(
      "1 subjects, 2 mutants, wall 1.25 s",
      "killed 1  survived 1  timeout 0  error 0  skipped 0",
      "score 50.0 %",
      "mean time per executed mutant 0.500 s",
      "Person#adult? comparison",
      "person.rb:2",
      "-  def adult?; @age >= 18; end\n+  def adult?; @age > 18; end"
    )
  end

  it "lists errors separately and does not call them killed" do
    text = render(report_of(result_for(:error, reason: "child killed by signal 9 during tests")))
    expect(text).to include("killed 0", "error 1", "Errors (not counted as killed):", "signal 9")
  end

  it "shows skip reasons, warnings and ignored survivors" do
    survivor = result_for(:survived)
    survivor.ignored = "equivalent: ages are integers"
    text = render(report_of(survivor, result_for(:skipped, reason: "no coverage"), warnings: ["stale entry"]))
    expect(text).to include("survived 1 (1 ignored)", "skipped: no coverage: 1", "warning: stale entry",
                            "ignored: equivalent: ages are integers")
  end

  it "prints n/a for the score when nothing ran" do
    expect(render(report_of)).to include("score n/a")
  end
end
