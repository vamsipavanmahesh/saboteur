# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::CoverageMap do
  let(:subject_under_test) { subjects_in("class A\n  def m\n    1\n    2\n  end\nend\n").first }
  let(:file) { subject_under_test.file }
  let(:map) do
    described_class.new(lines: { file => { 3 => %w[t2 t1], 4 => %w[t3 t1], 2 => %w[load] } },
                        tests: %w[t1 t2 t3 load])
  end

  it "returns the tests that executed any body line, in suite order, without duplicates" do
    expect(map.tests_for(subject_under_test)).to eq(%w[t1 t2 t3])
  end

  it "orders selected tests fastest first, then by suite order" do
    timed = described_class.new(lines: map.lines, tests: map.tests, durations: { "t1" => 0.5, "t2" => 0.01 })
    expect(timed.tests_for(subject_under_test)).to eq(%w[t2 t1 t3])
    expect(described_class.from_json(timed.to_json).durations).to eq("t1" => 0.5, "t2" => 0.01)
  end

  it "selects tests by line for a single edit" do
    expect(map.tests_for_lines(file, [4])).to eq(%w[t1 t3])
    expect(map.tests_for_lines(file, [99])).to eq([])
  end

  it "ignores the def line of a multi-line method (it runs at load time)" do
    expect(map.tests_for(subject_under_test)).not_to include("load")
  end

  it "returns nothing for files it has never seen" do
    expect(described_class.new(lines: {}, tests: []).tests_for(subject_under_test)).to eq([])
  end

  it "round-trips through JSON with integer line keys" do
    restored = described_class.from_json(map.to_json)
    expect(restored.lines).to eq(map.lines)
    expect(restored.tests_for(subject_under_test)).to eq(%w[t1 t2 t3])
  end

  it "refuses another format version" do
    expect { described_class.from_json('{"format":99,"lines":{},"tests":[]}') }
      .to raise_error(Saboteur::Error, /format/)
  end

  it "saves and loads a cache file, treating a corrupt file as a miss" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "nested", "map.json")
      map.save(path)
      expect(described_class.load(path).tests).to eq(map.tests)
      File.write(path, "{not json")
      expect(described_class.load(path)).to be_nil
    end
  end

  describe ".cache_key" do
    it "changes when a file's content or the extra inputs change" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a.rb")
        File.write(path, "1")
        first = described_class.cache_key(files: [path], extra: "x")
        expect(described_class.cache_key(files: [path], extra: "x")).to eq(first)
        expect(described_class.cache_key(files: [path], extra: "y")).not_to eq(first)
        File.write(path, "2")
        expect(described_class.cache_key(files: [path], extra: "x")).not_to eq(first)
      end
    end
  end

  describe "Recorder" do
    let(:recorder) { described_class::Recorder.new([file]) }
    let(:results) { [] }

    before do
      queue = results
      allow(Coverage).to receive(:result).with(stop: false, clear: true) { queue.shift || {} }
    end

    it "attributes each test's delta to that test, and outside-test lines to the next test's file" do
      results.push({ file => { lines: [nil, nil, 1, 0, nil, nil] } }, # before t1: before(:all)
                   { file => { lines: [nil, nil, 0, 2, nil, nil] } }, # during t1
                   {},                                                # before t2
                   { file => { lines: [nil, nil, 1, 0, nil, nil] } }) # during t2
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      recorder.test_started("t2", "/spec/a_spec.rb")
      recorder.test_finished("t2")
      built = recorder.result
      expect(built.tests).to eq(%w[t1 t2])
      expect(built.lines[file]).to eq(3 => %w[t2 t1], 4 => %w[t1])
    end

    it "suspends coverage while it processes a delta, so its own work is never attributed to a test" do
      allow(Coverage).to receive(:running?).and_return(true)
      allow(Coverage).to receive(:suspend)
      allow(Coverage).to receive(:resume)
      results.push({}, { file => { lines: [nil, nil, 1] } })
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(Coverage).to have_received(:suspend).twice
      expect(Coverage).to have_received(:resume).twice
    end

    it "ignores files that are not being mutated" do
      results.push({}, { "/other.rb" => { lines: [1] } })
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.lines).to eq({})
    end
  end
end
