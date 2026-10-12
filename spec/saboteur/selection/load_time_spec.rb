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
  it "does not report an uncovered line as load-only just because another line ran at load" do
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [], load_lines: { target.file => [4] })
    expect(map.ran_at_load?(target.file, [3])).to be(false)
  end

  it "preserves every field when adding load lines and when serializing" do
    map = Saboteur::Selection::CoverageMap.new(lines: { target.file => { 3 => ["t1"] } }, tests: ["t1"],
                                               durations: { "t1" => 0.75 }, build_seconds: 2.5)
    copy = map.with_load_lines({ target.file => [4] })
    restored = Saboteur::Selection::CoverageMap.from_json(copy.to_json)
    expect(restored.lines).to eq(map.lines)
    expect(restored.tests).to eq(map.tests)
    expect(restored.durations).to eq(map.durations)
    expect(restored.build_seconds).to eq(2.5)
    expect(restored.load_lines).to eq(target.file => [4])
    expect(JSON.parse(copy.to_json)["load_lines"]).to eq(target.file => [4])
  end

  it "loads an absent load-lines field from the current format as empty" do
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
    document = JSON.parse(map.to_json)
    document.delete("load_lines")
    expect(Saboteur::Selection::CoverageMap.from_json(JSON.generate(document)).load_lines).to eq({})
  end
  it "serializes unknown test durations without inventing a runtime" do
    map = Saboteur::Selection::CoverageMap.new(lines: { target.file => { 3 => ["t1"] } }, tests: ["t1"])
    expect(JSON.parse(map.to_json)["durations"]).to eq([nil])
    expect(Saboteur::Selection::CoverageMap.from_json(map.to_json).recorded_runtime(["t1"])).to be_nil
  end
  it "keeps method coverage when attaching load lines and round-tripping the combined map" do
    endless = subjects_in("class CombinedProbe\n  def value = 7\nend\n").first
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"], methods: { endless.file => { 2 => ["t1"] } })
    combined = map.with_load_lines(endless.file => [2])
    restored = Saboteur::Selection::CoverageMap.from_json(combined.to_json)
    expect(restored.methods).to eq(map.methods)
    expect(restored.load_lines).to eq(endless.file => [2])
    expect(restored.tests_for(endless)).to eq(["t1"])
    expect(restored.tests_for_edit(endless, [2])).to eq(["t1"])
  end

  it "rejects either old format-four cache shape" do
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
    document = JSON.parse(map.to_json)
    document["format"] = 4
    %w[methods load_lines].each do |field|
      legacy = document.reject { |key, _| key == field }
      expect { Saboteur::Selection::CoverageMap.from_json(JSON.generate(legacy)) }
        .to raise_error(Saboteur::Error, /format 4 is not 5/)
    end
  end
  it "accepts a combined cache with no method hits field as an empty methods table" do
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [], load_lines: { target.file => [3] })
    document = JSON.parse(map.to_json)
    document.delete("methods")
    restored = Saboteur::Selection::CoverageMap.from_json(JSON.generate(document))
    expect(restored.methods).to eq({})
    expect(restored.load_lines).to eq(target.file => [3])
  end
end
