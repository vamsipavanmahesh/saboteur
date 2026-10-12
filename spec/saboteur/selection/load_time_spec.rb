# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "load-time coverage" do
  let(:target) { subjects_in("class LoadTimeProbe\n  def value\n    7\n  end\nend\n").first }

  it "keeps load-only lines separate from example coverage and round-trips them" do
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [], load_lines: { target.file => [3] })
    restored = Saboteur::Selection::CoverageMap.from_json(map.to_json)
    expect(restored.ran_at_load?(target.file, target.coverage_lines)).to be(true)
    expect(restored.tests_for(target)).to eq([])
  end

  it "does not call a line load-only when a test later hits it" do
    map = Saboteur::Selection::CoverageMap.new(lines: { target.file => { 3 => ["t1"] } }, tests: ["t1"],
                                               load_lines: { target.file => [3] })
    expect(map.ran_at_load?(target.file, [3])).to be(false)
  end

  it "keeps a copy with load lines from carrying any test coverage" do
    map = Saboteur::Selection::CoverageMap.new(lines: { target.file => { 3 => ["t1"] } }, tests: ["t1"])
    with_load = map.with_load_lines({ target.file => [4] })
    expect(with_load.tests_for(target)).to eq(["t1"])
    expect(with_load.ran_at_load?(target.file, [4])).to be(true)
    expect(map.load_lines).to eq({})
  end
end
