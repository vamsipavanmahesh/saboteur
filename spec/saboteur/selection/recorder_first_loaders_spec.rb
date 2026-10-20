# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# A file's load-time lines are credited to whichever test first made it load,
# so the map records that test (#46): a partial rerun cannot tell load-time
# hits from run-time ones, but it can tell who was first.
RSpec.describe Saboteur::Selection::Recorder, "first loaders (#46)" do
  let(:a_file) { Saboteur::Selection::CoverageMap.canonical(__FILE__) }
  let(:b_file) { Saboteur::Selection::CoverageMap.canonical(File.expand_path("coverage_map_spec.rb", __dir__)) }
  let(:recorder) { described_class.new([a_file, b_file]) }

  def hit(*paths)
    snapshot = paths.to_h { |path| [path, { lines: [nil, 1], branches: {} }] }
    allow(Saboteur::CoverageReads).to receive(:result).and_return(snapshot)
    allow(Coverage).to receive(:running?).and_return(false)
  end

  def run_test(id, spec_file, *paths)
    hit
    recorder.test_started(id, spec_file)
    hit(*paths)
    recorder.test_finished(id)
  end

  it "hands each result its own copy of the first loaders" do
    run_test("t1", "s1", a_file)
    map = recorder.result
    run_test("t2", "s1", b_file)
    expect(map.first_loaders).to eq(a_file => "t1")
  end

  it "records the first test in which a file showed a hit, and keeps it when later tests hit it too" do
    run_test("t1", "s1", a_file)
    run_test("t2", "s1", a_file, b_file)
    run_test("t3", "s2", b_file)

    expect(recorder.result.first_loaders).to eq(a_file => "t1", b_file => "t2")
  end

  it "does not name a test for a file already hit outside any test (a spec file's own load)" do
    hit(a_file)
    recorder.test_started("t1", "s1")
    hit(a_file)
    recorder.test_finished("t1")

    expect(recorder.result.first_loaders).to eq({})
  end

  it "survives a save and a load, and a map without the record knows nothing" do
    run_test("t1", "s1", a_file)
    map = Saboteur::Selection::CoverageMap.from_json(recorder.result.to_json)
    expect(map.first_loaders).to eq(a_file => "t1")

    bare = JSON.parse(recorder.result.to_json).tap { |data| data.delete("first_loaders") }
    expect(Saboteur::Selection::CoverageMap.from_data(bare).first_loaders).to be_nil
  end

  it "ignores a restored table that is not file names to known test ids" do
    run_test("t1", "s1", a_file)
    data = JSON.parse(recorder.result.to_json)

    [{ a_file => "nope" }, { a_file => 3 }, { a_file => "t1", b_file => "nope" }, "x", [1]].each do |bad|
      expect(Saboteur::Selection::CoverageMap.from_data(data.merge("first_loaders" => bad)).first_loaders).to be_nil
    end
  end

  it "is kept by with_load_lines and with_preloaded" do
    run_test("t1", "s1", a_file)
    map = recorder.result

    expect(map.with_load_lines({}).first_loaders).to eq(a_file => "t1")
    expect(map.with_preloaded([]).first_loaders).to eq(a_file => "t1")
  end
end
