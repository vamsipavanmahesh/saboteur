# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::BaselineTail, "golden pins" do
  # The goldens pin the UTF-8 glyphs; force a UTF-8 locale so a
  # C-locale CI leg does not downgrade them to their ASCII fallbacks.
  around do |example|
    saved = ENV.to_h.slice("LC_ALL", "LC_CTYPE", "LANG")
    ENV["LC_ALL"] = "C.UTF-8"
    example.run
  ensure
    keys = %w[LC_ALL LC_CTYPE LANG]
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
  end

  def palette(mode)
    Saboteur::Reporter::Palette.for(StringIO.new, mode:)
  end

  def gate(new_ids:, exceeded: false, accepted: 411, changed: 0, resolved: 1, timeouts: 0, score: :default)
    score = { "current" => 71.0, "baseline" => 70.8, "exceeded" => exceeded } if score == :default
    comparison = instance_double(Saboteur::Baseline::Comparison,
                                 categories: { "accepted" => Array.new(accepted), "new" => new_ids,
                                               "changed" => Array.new(changed),
                                               "resolved_kills" => Array.new(resolved),
                                               "detected_timeouts" => Array.new(timeouts),
                                               "unmatched" => [], "errors" => [] },
                                 score:)
    instance_double(Saboteur::Baseline::RunGate, comparison:, new_survivor_ids: new_ids,
                                                 score_exceeded?: exceeded)
  end

  def render(gate, exit_code, mode: :never)
    out = StringIO.new
    described_class.new(out, palette(mode)).call(gate, exit_code)
    out.string
  end

  it "renders the failing tail: matched line, verdict, indented hint" do
    expect(render(gate(new_ids: %w[a1 b2]), 1)).to eq(
      "saboteur: 412 mutants matched the baseline (411 unchanged, 1 fixed) · 2 new survivors\n" \
      "✗ exit 1 - 2 new survivors vs baseline (score 71.0%, was 70.8%)\n  " \
      "re-baseline deliberately: saboteur baseline accept · run full weekly\n"
    )
  end

  it "paints the failure parts with the contract tokens when colour is on" do
    expect(render(gate(new_ids: %w[a1 b2]), 1, mode: :always)).to eq(
      "saboteur: \e[2m412 mutants matched the baseline (411 unchanged, 1 fixed)\e[0m · " \
      "\e[31;1m2 new survivors\e[0m\n" \
      "\e[31;1m✗ exit 1 - 2 new survivors vs baseline (score 71.0%, was 70.8%)\e[0m\n  " \
      "\e[36mre-baseline deliberately: saboteur baseline accept · run full weekly\e[0m\n"
    )
  end

  it "renders the passing tail: matched line with both scores, drift hint" do
    expect(render(gate(new_ids: [], score: { "current" => 71.2, "baseline" => 70.8, "exceeded" => false }),
                  0)).to eq(
                    "saboteur: 412 mutants matched the baseline, no new survivors " \
                    "- score 71.2% (baseline 70.8%)\n" \
                    "re-baseline deliberately · run without --baseline weekly to catch drift\n"
                  )
  end

  it "paints the passing tail with the contract tokens when colour is on" do
    expect(render(gate(new_ids: [], score: { "current" => 71.2, "baseline" => 70.8, "exceeded" => false }),
                  0, mode: :always)).to eq(
                    "saboteur: \e[2m412 mutants matched the baseline\e[0m, " \
                    "\e[32mno new survivors\e[0m - score 71.2% (baseline 70.8%)\n" \
                    "\e[36mre-baseline deliberately · run without --baseline weekly to catch drift\e[0m\n"
                  )
  end

  it "names a score-only failure and its epsilon breach" do
    expect(render(gate(new_ids: [], exceeded: true,
                       score: { "current" => 70.9, "baseline" => 71.4, "exceeded" => true }), 1))
      .to include("✗ exit 1 - score drop beyond epsilon vs baseline (score 70.9%, was 71.4%)\n")
  end

  it "joins both failure reasons" do
    expect(render(gate(new_ids: %w[a1], exceeded: true), 1))
      .to include("✗ exit 1 - 1 new survivor and score drop beyond epsilon vs baseline (score 71.0%, was 70.8%)\n")
  end

  it "shows each nonzero breakdown part with distinct unchanged and fixed counts" do
    expect(render(gate(new_ids: %w[a1], accepted: 2, changed: 1, resolved: 1, timeouts: 2), 1)).to include(
      "saboteur: 6 mutants matched the baseline (3 unchanged, 3 fixed) · 1 new survivor
"
    )
  end

  it "omits the unchanged part when every match was fixed" do
    expect(render(gate(new_ids: %w[a1], accepted: 0, changed: 0, resolved: 1, timeouts: 0), 1)).to include(
      "saboteur: 1 mutant matched the baseline (1 fixed) · 1 new survivor
"
    )
  end

  it "omits the breakdown when nothing matched" do
    expect(render(gate(new_ids: %w[a1 b2], accepted: 0, changed: 0, resolved: 0, timeouts: 0), 1)).to include(
      "saboteur: 0 mutants matched the baseline · 2 new survivors
"
    )
  end

  it "omits the verdict's score clause when the comparison has no scored mutants" do
    expect(render(gate(new_ids: %w[a1], score: nil), 1)).to include(
      "✗ exit 1 - 1 new survivor vs baseline
"
    )
  end

  it "singularizes one matched mutant, one unchanged, one new survivor" do
    expect(render(gate(new_ids: %w[a1], accepted: 0, resolved: 0, changed: 1), 1)).to include(
      "saboteur: 1 mutant matched the baseline (1 unchanged) · 1 new survivor\n"
    )
  end

  it "prints the failing hint on an incomplete gated run too" do
    text = render(gate(new_ids: []), 3)
    expect(text).to include("re-baseline deliberately: saboteur baseline accept · run full weekly\n")
    expect(text).not_to include("catch drift")
  end

  def terminal_render(exit_code, baseline_gate: nil)
    report = Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1.25,
                                  root: File.dirname(person_subject.file), seed: 1)
    out = StringIO.new
    Saboteur::Reporter::Terminal.new(out, exit_code:, baseline_gate:).call(report)
    out.string
  end

  it "replaces the terminal's canonical tally and owns the exit-1 verdict" do
    text = terminal_render(1, baseline_gate: gate(new_ids: %w[a1 b2]))
    expect(text).to include(
      "saboteur: 412 mutants matched the baseline (411 unchanged, 1 fixed) · 2 new survivors
",
      "✗ exit 1 - 2 new survivors vs baseline (score 71.0%, was 70.8%)
"
    )
    expect(text).not_to include("✗ exit 1 - 1 survivor
")
  end

  it "keeps the ordinary incomplete verdict on a gated run's exit 3" do
    text = terminal_render(3, baseline_gate: gate(new_ids: %w[a1 b2]))
    expect(text).to include("saboteur: 412 mutants matched the baseline (411 unchanged, 1 fixed) · 2 new survivors
",
                            "✗ exit 3 - run incomplete; the score is not a verified result
")
  end

  it "keeps the ordinary tally and verdict without a gate" do
    text = terminal_render(1)
    expect(text).to include("✗ exit 1 - 1 survivor
")
    expect(text).not_to include("matched the baseline")
  end

  it "omits the score clause when the comparison has no scored mutants" do
    gate = gate(new_ids: [], score: nil)
    expect(render(gate, 0)).to include("saboteur: 412 mutants matched the baseline, no new survivors\n")
  end
end
