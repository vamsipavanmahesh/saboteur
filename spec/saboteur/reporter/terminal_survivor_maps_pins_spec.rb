# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Terminal wires the cached whole-suite map and the run's own map into the
# survivor list (review C1): the run map says which covering specs this run
# actually loaded, the whole-suite map names the rest.
RSpec.describe Saboteur::Reporter::Terminal, "whole-suite map wiring" do
  let(:out) { StringIO.new }

  it "hands both maps to the survivor list, marking specs the run never loaded" do
    survivor = result_for(:survived, covered_by: ["./spec/outside_spec.rb[1:1]"])
    report = report_of(survivor)
    calc = "./spec/calculator_spec.rb[2:1]"
    flow = "./spec/flow_spec.rb[1:1]"
    file = Saboteur::Selection::CoverageMap.canonical(person_subject.file)
    whole = Saboteur::Selection::CoverageMap.new(
      lines: { file => person_subject.coverage_lines.to_h { |line| [line, [calc, flow]] } }, tests: [calc, flow]
    )
    run = Saboteur::Selection::CoverageMap.new(
      lines: { file => person_subject.coverage_lines.to_h { |line| [line, [calc]] } }, tests: [calc]
    )

    described_class.new(out, whole_suite_map: whole, run_map: run).call(report)

    expect(out.string).to include("covered by 2 specs, incl. ./spec/flow_spec.rb[1:1] (not run here)")
  end
end
