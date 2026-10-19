# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Selection::CoverageMap do
  let(:subject_under_test) { subjects_in("class A\n  def m\n    1\n    2\n  end\nend\n").first }
  let(:file) { subject_under_test.file }
  let(:map) do
    described_class.new(lines: { file => { 3 => %w[t2 t1], 4 => %w[t3 t1], 2 => %w[load] } },
                        tests: %w[t1 t2 t3 load])
  end

  it "flags a subject every test covers whose lines also ran at load (#575)" do
    boot_map = described_class.new(lines: { file => { 3 => %w[t1 t2], 4 => %w[t1 t2] } },
                                   tests: %w[t1 t2], load_lines: { file => [2, 3, 4] })
    expect(boot_map.boot_once?(subject_under_test)).to be(true)
    expect(boot_map.boot_credited?(file, [3])).to be(true)
  end

  it "does not flag partial coverage or a subject that never ran at load (#575)" do
    partial = described_class.new(lines: { file => { 3 => %w[t1] } }, tests: %w[t1 t2],
                                  load_lines: { file => [3] })
    expect(partial.boot_once?(subject_under_test)).to be(false)
    full_no_boot = described_class.new(lines: { file => { 3 => %w[t1 t2], 4 => %w[t1 t2] } },
                                       tests: %w[t1 t2], load_lines: { file => [2] })
    expect(full_no_boot.boot_once?(subject_under_test)).to be(false)
    expect(full_no_boot.boot_credited?(file, [3])).to be(false)
    expect(described_class.new(lines: {}, tests: []).boot_once?(subject_under_test)).to be(false)
  end

  it "never flags a constant subject, however boot-shaped its coverage is (#575)" do
    Dir.mktmpdir do |dir|
      constant_file = File.join(dir, "constants.rb")
      File.write(constant_file, "MAP = { a: 1 }.freeze\n")
      constant = Saboteur::ConstantSubjectFinder.new.call(constant_file).subjects.first
      # Every test reads the constant and its assignment ran at load: the
      # most boot-shaped coverage a constant can have.
      constant.consumer_lines = { constant.file => [1] }
      cfile = described_class.canonical(constant.file)
      boot_map = described_class.new(lines: { cfile => { 1 => %w[t1 t2] } },
                                     tests: %w[t1 t2], load_lines: { cfile => [1] })
      expect(boot_map.boot_once?(constant)).to be(false)
    end
  end

  it "does not flag anything on an empty map, even with load-line evidence (#575)" do
    empty = described_class.new(lines: {}, tests: [], load_lines: { file => [3] })
    expect(empty.boot_once?(subject_under_test)).to be(false)
  end

  it "flags a subject when only one of its body lines ran at load (#575)" do
    one_line = described_class.new(lines: { file => { 3 => %w[t1 t2], 4 => %w[t1 t2] } },
                                   tests: %w[t1 t2], load_lines: { file => [3] })
    expect(one_line.boot_once?(subject_under_test)).to be(true)
  end

  describe ".combine" do
    it "reads two disjoint shard maps as one build (#741)" do
      left = described_class.new(lines: { file => { 3 => %w[t1], 4 => %w[t2] } }, tests: %w[t1 t2],
                                 durations: { "t1" => 0.4, "t2" => 0.1 }, load_lines: { file => [3, 2] },
                                 loaded_files: [file], build_seconds: 3)
      right = described_class.new(lines: { file => { 3 => %w[t3], 5 => %w[t4] } }, tests: %w[t3 t4],
                                  durations: { "t3" => 0.3, "t4" => 0.2 }, load_lines: { file => [4] },
                                  loaded_files: [file], build_seconds: 5)
      combined = described_class.combine([left, right])

      expect(combined.tests).to eq(%w[t1 t2 t3 t4])
      expect(combined.tests_for_lines(file, [3])).to eq(%w[t3 t1])
      expect(combined.tests_for(subject_under_test)).to eq(%w[t2 t4 t3 t1])
      expect(combined.recorded_runtime(%w[t1 t4])).to be_within(1e-9).of(0.6)
      expect(combined.files_for(%w[t4 t1])).to eq([file])
      expect(combined.load_lines).to eq(file => [2, 3, 4])
      expect(combined.loaded_files).to eq([file])
      expect(combined.build_seconds).to eq(8)
    end

    it "unions method, branch and load-method evidence across shards (#741)" do
      left = described_class.new(lines: {}, tests: %w[t1], methods: { file => { 2 => %w[t1] } },
                                 branches: { file => { [3, 0, 4, 0] => %w[t1] } },
                                 load_methods: { file => [2] }, preloaded: [file])
      right = described_class.new(lines: {}, tests: %w[t2], methods: { file => { 2 => %w[t2], 6 => %w[t2] } },
                                  branches: { file => { [3, 0, 4, 0] => %w[t2] } },
                                  load_methods: { file => [6] })
      combined = described_class.combine([left, right])

      expect(combined.methods).to eq(file => { 2 => %w[t1 t2], 6 => %w[t2] })
      expect(combined.branches).to eq(file => { [3, 0, 4, 0] => %w[t1 t2] })
      expect(combined.load_methods).to eq(file => [2, 6])
      expect(combined.preloaded).to contain_exactly(described_class.canonical(file))
    end

    it "round-trips a combined map through JSON without losing evidence (#741)" do
      left = described_class.new(lines: { file => { 3 => %w[t1] } }, tests: %w[t1],
                                 durations: { "t1" => 0.5 }, branches: { file => { [3, 0, 4, 0] => %w[t1] } })
      right = described_class.new(lines: { file => { 3 => %w[t2] } }, tests: %w[t2],
                                  durations: { "t2" => 0.25 })
      combined = described_class.from_json(described_class.combine([left, right]).to_json)

      expect(combined.tests).to eq(%w[t1 t2])
      expect(combined.tests_for_lines(file, [3])).to eq(%w[t2 t1])
      expect(combined.recorded_runtime(%w[t1 t2])).to eq(0.75)
    end

    it "keeps a nil build_seconds only when no shard recorded one (#741)" do
      timed = described_class.new(lines: {}, tests: %w[t1], build_seconds: 4)
      plain = described_class.new(lines: {}, tests: %w[t2])

      expect(described_class.combine([timed, plain]).build_seconds).to eq(4)
      expect(described_class.combine([plain, described_class.new(lines: {}, tests: %w[t3])]).build_seconds).to be_nil
    end

    it "reads a one-shard build as an equal map and refuses an empty build (#741)" do
      map = described_class.new(lines: { file => { 3 => %w[t1] } }, tests: %w[t1], durations: { "t1" => 0.5 },
                                build_seconds: 2)
      combined = described_class.combine([map])

      expect(combined.tests).to eq(%w[t1])
      expect(combined.tests_for_lines(file, [3])).to eq(%w[t1])
      expect(combined.recorded_runtime(%w[t1])).to eq(0.5)
      expect(combined.build_seconds).to eq(2)
      expect { described_class.combine([]) }.to raise_error(ArgumentError, "no coverage maps to combine")
    end

    it "refuses shards that repeat a test id: the partition is not disjoint (#741)" do
      left = described_class.new(lines: {}, tests: %w[t1 t2])
      right = described_class.new(lines: {}, tests: %w[t2 t3])

      expect { described_class.combine([left, right]) }
        .to raise_error(ArgumentError, "coverage maps share test ids: t2")

      first = described_class.new(lines: {}, tests: %w[t9 t5 t1])
      second = described_class.new(lines: {}, tests: %w[t1 t7 t9])

      expect { described_class.combine([first, second]) }
        .to raise_error(ArgumentError, "coverage maps share test ids: t1, t9")

      many_left = described_class.new(lines: {}, tests: %w[t8 t4 t2 t6 t1])
      many_right = described_class.new(lines: {}, tests: %w[t6 t1 t4 t2 t3])

      expect { described_class.combine([many_left, many_right]) }
        .to raise_error(ArgumentError, "coverage maps share test ids: t1, t2, t4")
    end
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

  it "sorts tests without a recorded duration last instead of failing" do
    partial = described_class.new(lines: map.lines, tests: map.tests, durations: { "t2" => 0.01 })
    expect(partial.tests_for(subject_under_test)).to eq(%w[t2 t1 t3])
  end

  it "ignores the def line of a multi-line method (it runs at load time)" do
    expect(map.tests_for(subject_under_test)).not_to include("load")
  end

  it "falls back to method coverage for a subject with no line hits (endless defs)" do
    endless = subjects_in("class A\n  def m = 1\nend\n").first
    endless_map = described_class.new(lines: {}, tests: %w[t1 t2], methods: { endless.file => { 2 => %w[t2 t1] } })
    expect(endless_map.tests_for(endless)).to eq(%w[t1 t2])
  end

  it "prefers line coverage over method coverage when both exist" do
    both = described_class.new(lines: { file => { 3 => %w[t3] } }, tests: %w[t1 t3],
                               methods: { file => { 2 => %w[t1] } })
    expect(both.tests_for(subject_under_test)).to eq(%w[t3])
  end

  it "only counts method hits whose def falls inside the subject" do
    by_method = described_class.new(lines: {}, tests: %w[t1 t2], methods: { file => { 1 => %w[t1], 2 => %w[t2] } })
    expect(by_method.tests_for(subject_under_test)).to eq(%w[t2])
  end

  it "keeps an uncovered branch as no coverage while an endless def falls back to methods" do
    branched = subjects_in("class A\n  def m\n    1\n    2\n  end\nend\n").first
    map = described_class.new(lines: { branched.file => { 3 => %w[t1] } }, tests: %w[t1 t2],
                              methods: { branched.file => { 2 => %w[t1 t2] } })
    expect(map.tests_for_edit(branched, [4])).to eq([])
    endless = subjects_in("class A\n  def m = 1\nend\n").first
    endless_map = described_class.new(lines: {}, tests: %w[t1 t2], methods: { endless.file => { 2 => %w[t2 t1] } })
    expect(endless_map.tests_for_edit(endless, [2])).to eq(%w[t1 t2])
  end

  it "is empty only when neither lines nor methods recorded anything" do
    expect(described_class.new(lines: {}, tests: []).empty?).to be(true)
    expect(described_class.new(lines: {}, tests: [], methods: { file => { 2 => %w[t1] } }).empty?).to be(false)
    expect(map.empty?).to be(false)
  end

  # Spec files sit in the same map as the included files, so whole-map
  # emptiness cannot tell a build that recorded test code only.
  it "reports emptiness for a chosen file set only" do
    other = File.join(File.dirname(file), "other_spec.rb")
    spec_only = described_class.new(lines: { other => { 2 => %w[t1] } }, tests: %w[t1])
    expect(spec_only.empty_for?([file])).to be(true)
    expect(spec_only.empty_for?([other])).to be(false)
    expect(spec_only.empty?).to be(false)
  end

  # Each recorded kind counts, and the file set is canonicalized before the
  # lookup: the recorder stores canonical paths.
  it "checks methods and load lines too, under any spelling of the file" do
    method_only = described_class.new(lines: {}, tests: %w[t1], methods: { file => { 2 => %w[t1] } })
    expect(method_only.empty_for?([file])).to be(false)
    load_only = described_class.new(lines: {}, tests: %w[t1], load_lines: { file => [3] })
    expect(load_only.empty_for?([file])).to be(false)
    dotted = File.join(File.dirname(file), ".", File.basename(file))
    with_hits = described_class.new(lines: { file => { 2 => %w[t1] } }, tests: %w[t1])
    expect(with_hits.empty_for?([dotted])).to be(false)
  end

  # A def-time macro's caller ran in the boot's spec load, so the boot
  # method counters name the def line - and no test calls it again (#409).
  it "knows a def line the boot called and no test calls again" do
    map = described_class.new(lines: {}, tests: %w[t1], load_methods: { file => [2] })
    expect(map.called_only_at_load?(file, 2)).to be(true)
  end

  it "does not call a def load-only when a test or hook calls it post-boot" do
    map = described_class.new(lines: {}, tests: %w[t1], load_methods: { file => [2] },
                              methods: { file => { 2 => %w[t1] } })
    expect(map.called_only_at_load?(file, 2)).to be(false)
    plain = described_class.new(lines: {}, tests: %w[t1], methods: { file => { 2 => %w[t1] } })
    expect(plain.called_only_at_load?(file, 2)).to be(false)
  end

  it "round-trips load method coverage through JSON" do
    map = described_class.new(lines: {}, tests: %w[t1], load_methods: { file => [2, 7] })
    expect(described_class.from_json(map.to_json).load_methods).to eq(file => [2, 7])
  end

  it "round-trips method coverage through JSON" do
    with_methods = described_class.new(lines: {}, tests: %w[t1 t2], methods: { file => { 2 => %w[t2 t1] } })
    expect(described_class.from_json(with_methods.to_json).methods).to eq(file => { 2 => %w[t2 t1] })
  end

  it "returns nothing for files it has never seen" do
    expect(described_class.new(lines: {}, tests: []).tests_for(subject_under_test)).to eq([])
  end

  it "rounds durations to six decimals through the JSON round-trip (#353)" do
    map = described_class.new(lines: {}, tests: %w[t1], durations: { "t1" => 0.123456789 })
    expect(described_class.from_json(map.to_json).durations).to eq("t1" => 0.123457)
  end

  it "keeps the loaded source list when load lines are merged in (#353)" do
    map = described_class.new(lines: {}, tests: [], loaded_files: ["/app/support/helper.rb"])
    expect(map.with_load_lines({ "boot.rb" => [1, 2] }).loaded_files).to eq(["/app/support/helper.rb"])
  end

  it "preserves every field through with_preloaded and answers preloaded? for exact and absent files" do
    full = described_class.new(lines: { "/app/lib/a.rb" => { 3 => ["t1"] } }, tests: ["t1"], build_seconds: 2.5,
                               durations: { "t1" => 0.5 }, methods: { "/app/lib/a.rb" => { 4 => ["t1"] } },
                               load_lines: { "/app/lib/a.rb" => [1] }, load_methods: { "/app/lib/a.rb" => [10] },
                               branches: { "/app/lib/a.rb" => { [5, :then, 6] => ["t1"] } },
                               loaded_files: ["/app/lib/a.rb"])

    map = full.with_preloaded(["/app/lib/a.rb"])

    expect(map.lines).to eq(full.lines)
    expect(map.tests).to eq(full.tests)
    expect(map.build_seconds).to eq(2.5)
    expect(map.durations).to eq("t1" => 0.5)
    expect(map.methods).to eq("/app/lib/a.rb" => { 4 => ["t1"] })
    expect(map.load_lines).to eq("/app/lib/a.rb" => [1])
    expect(map.load_methods).to eq("/app/lib/a.rb" => [10])
    expect(map.branches).to eq("/app/lib/a.rb" => { [5, :then, 6] => ["t1"] })
    expect(map.loaded_files).to eq(["/app/lib/a.rb"])
    expect(map.preloaded?("/app/lib/a.rb")).to be(true)
    expect(map.preloaded?("/app/lib/b.rb")).to be(false)
    expect(full.preloaded?("/app/lib/a.rb")).to be(false)
  end

  it "matches preloaded files under any spelling of their path (symlinked root)" do
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, "real"))
      Dir.mkdir(File.join(dir, "real", "lib"))
      target = File.join(dir, "real", "lib", "a.rb")
      File.write(target, "1\n")
      File.symlink(File.join(dir, "real"), File.join(dir, "link"))
      spelled = File.join(dir, "link", "lib", "a.rb")

      map = described_class.new(lines: {}, tests: []).with_preloaded([spelled])

      expect(map.preloaded?(target)).to be(true)
      expect(map.preloaded?(spelled)).to be(true)
    end
  end

  it "keeps the loaded source list through the JSON round-trip (#353)" do
    map = described_class.new(lines: {}, tests: [], loaded_files: ["/app/support/helper.rb"])
    expect(described_class.from_json(map.to_json).loaded_files).to eq(["/app/support/helper.rb"])
  end

  it "round-trips through JSON with integer line keys" do
    timed = described_class.new(lines: map.lines, tests: map.tests, build_seconds: 1.5)
    restored = described_class.from_json(timed.to_json)
    expect(restored.build_seconds).to eq(1.5)
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
    it "treats a missing file as an input of its own" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "gone.rb")
        missing = described_class.cache_key(files: [path], extra: "x")
        File.write(path, "")
        expect(described_class.cache_key(files: [path], extra: "x")).not_to eq(missing)
      end
    end

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
    let(:recorder) { Saboteur::Selection::Recorder.new([file]) }
    let(:results) { [] }

    before do
      # Keep mocked counters off the real API used by an outer dogfood recorder.
      fake_coverage = Module.new
      fake_coverage.define_singleton_method(:result) { |**| {} }
      fake_coverage.define_singleton_method(:running?) { false }
      fake_coverage.define_singleton_method(:suspend) { nil }
      fake_coverage.define_singleton_method(:resume) { nil }
      stub_const("Coverage", fake_coverage)
      queue = results
      allow(Coverage).to receive(:result).with(stop: false, clear: true) { queue.shift || {} }
      # Never touch the real Coverage: when saboteur measures its own suite,
      # suspending it here would hide these very examples from the map.
      allow(Coverage).to receive(:running?).and_return(false)
    end

    it "ignores synthetic full-expression arms that include a modifier condition" do
      branch = [:if, 0, 3, 4, 3, 15]
      yes = [:then, 1, 3, 4, 3, 10]
      synthetic = [:else, 2, 3, 4, 3, 15]
      results.push({}, { file => { lines: [], branches: { branch => { yes => 0, synthetic => 1 } } } })
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.branches).to eq(file => { [3, 4, 3, 10] => [] })
    end

    it "drops a case arm whose span swallows its siblings" do
      # Ruby spans a `when X` arm with a bare `nil` body from the `when` to
      # the case's end, containing the sibling arms. Recording that span
      # lets it intersect and narrow selection for edits inside the
      # siblings it swallows (dogfood: hazard_guard's condition mutants
      # survived although a selecting test killed them).
      kase = [:case, 0, 10, 8, 16, 11]
      nil_arm = [:when, 1, 11, 8, 15, 27]
      write_arm = [:when, 2, 13, 10, 13, 60]
      call_arm = [:when, 3, 14, 10, 14, 53]
      else_arm = [:else, 4, 15, 10, 15, 27]
      results.push({}, { file => { lines: [],
                                   branches: { kase => { nil_arm => 1, write_arm => 1, call_arm => 0,
                                                         else_arm => 0 } } } })
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.branches).to eq(file => { [13, 10, 13, 60] => ["t1"], [14, 10, 14, 53] => [],
                                                       [15, 10, 15, 27] => [] })
    end

    it "contains? compares span endpoints lexically" do
      contains = ->(outer, inner) { recorder.send(:contains?, outer, inner) }
      # Same start line: the column decides which span starts first.
      expect(contains.call([1, 5, 3, 0], [1, 7, 2, 0])).to be(true)
      expect(contains.call([1, 7, 3, 0], [1, 5, 2, 0])).to be(false)
      # Equal spans contain each other; record_branches excludes them itself.
      expect(contains.call([1, 0, 5, 0], [1, 0, 5, 0])).to be(true)
      # A strictly inner span is not an outer.
      expect(contains.call([2, 0, 3, 0], [1, 0, 5, 0])).to be(false)
      # Equal starts: the end alone makes the wider span the outer.
      expect(contains.call([2, 5, 9, 0], [2, 5, 3, 0])).to be(true)
    end

    it "keeps untaken arms and attributes taken branches to each test" do
      branch = [:if, 0, 3, 4, 3, 15]
      yes = [:then, 1, 3, 8, 3, 10]
      no = [:else, 2, 3, 13, 3, 15]
      results.push({}, { file => { lines: [], branches: { branch => { yes => 1, no => 0 } } } })
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.branches).to eq(file => { [3, 8, 3, 10] => ["t1"], [3, 13, 3, 15] => [] })
    end

    it "attributes branches outside examples to the next test file" do
      branch = [:if, 0, 3, 4, 3, 15]
      yes = [:then, 1, 3, 8, 3, 10]
      results.push({ file => { lines: [], branches: { branch => { yes => 1 } } } }, {})
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.branches).to eq(file => { [3, 8, 3, 10] => ["t1"] })
    end

    it "records a real, non-negative duration with the real clock" do
      results.push({}, {})
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.durations["t1"]).to be_a(Float).and(be >= 0)
    end

    it "carries the build time onto the map" do
      results.push({}, {})
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result(build_seconds: 12.5).build_seconds).to eq(12.5)
    end

    it "ignores method keys with zero hits" do
      key = ["A", :m, 2, 2, 2, 10]
      results.push({}, { file => { lines: [], methods: { key => 0 } } })
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.methods).to eq({})
    end

    it "records how long each test took" do
      results.push({}, {})
      allow(recorder).to receive(:monotonic).and_return(10.0, 10.25)
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.durations).to eq("t1" => 0.25)
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

    it "records per-test method hits, for endless defs whose lines never count" do
      key = ["A", :m, 2, 2, 2, 10]
      results.push({}, { file => { lines: [nil, nil], methods: { key => 1 } } })
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.methods[file]).to eq(2 => %w[t1])
    end

    it "attributes method calls outside a test to the next test's file" do
      key = ["A", :m, 2, 2, 2, 10]
      results.push({ file => { lines: [], methods: { key => 1 } } }, {})
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.methods[file]).to eq(2 => %w[t1])
    end

    it "ignores files that are not being mutated" do
      results.push({}, { "/other.rb" => { lines: [1] } })
      recorder.test_started("t1", "/spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.lines).to eq({})
    end
  end

  # Survivor kills for #480's load tracking (#480 dogfood gate).
  it "keeps method, branch and duration evidence when attaching load lines" do
    map = described_class.new(lines: { file => { 2 => %w[t1] } }, tests: %w[t1],
                              methods: { file => { 2 => %w[t1] } }, durations: { "t1" => 0.5 },
                              branches: { file => { 4 => %w[t1] } })
    merged = map.with_load_lines({ file => [3] }, { file => [2] })
    expect(merged.methods).to eq(file => { 2 => %w[t1] })
    expect(merged.branches).to eq(file => { 4 => %w[t1] })
    expect(merged.durations).to eq("t1" => 0.5)
    expect(merged.load_lines).to eq(file => [3])
    expect(merged.load_methods).to eq(file => [2])
  end

  it "is not load-only when the boot never called the def, even with no test callers" do
    plain = described_class.new(lines: {}, tests: %w[t1])
    expect(plain.called_only_at_load?(file, 2)).to be(false)
  end

  it "is not load-only when the boot called a different line of the file" do
    map = described_class.new(lines: {}, tests: %w[t1], load_methods: { file => [9] })
    expect(map.called_only_at_load?(file, 2)).to be(false)
  end

  # The recorder stores canonical paths, so the lookup must canonicalize
  # the queried spelling too (#480 dogfood).
  it "canonicalizes the queried file before the load-methods lookup" do
    map = described_class.new(lines: {}, tests: %w[t1], load_methods: { file => [2] })
    dotted = File.join(File.dirname(file), ".", File.basename(file))
    expect(map.called_only_at_load?(dotted, 2)).to be(true)
  end

  # A sibling def with test callers does not make this def called: the
  # per-line fetch, not the file's entry, answers the question (#480
  # dogfood).
  it "stays load-only for a def no test calls when another def of the file has callers" do
    map = described_class.new(lines: {}, tests: %w[t1], load_methods: { file => [2] },
                              methods: { file => { 7 => %w[t1] } })
    expect(map.called_only_at_load?(file, 2)).to be(true)
  end

  it "decodes an absent key as empty int lists" do
    expect(described_class.int_lists({}, "load_methods")).to eq({})
    expect(described_class.int_lists({ "load_methods" => { "a.rb" => %w[1 2] } }, "load_methods"))
      .to eq("a.rb" => [1, 2])
  end

  it "names the source files the given tests touched, sorted and deduped (#197)" do
    map = described_class.new(
      lines: { "/a/helper.rb" => { 3 => %w[t1 t2], 9 => ["t1"] }, "/a/other.rb" => { 1 => ["t2"] } },
      tests: %w[t1 t2]
    )
    expect(map.files_for(["t1"])).to eq(["/a/helper.rb"])
    expect(map.files_for(%w[t1 t2])).to eq(["/a/helper.rb", "/a/other.rb"])
    expect(map.files_for(["t3"])).to eq([])
  end
end

RSpec.describe Saboteur::Selection::CoverageMap, "constant subjects (issue #306)" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def constant_subject(consumer_lines)
    file = File.join(@root, "constants.rb")
    File.write(file, "MAP = { a: 1 }.freeze\n")
    subject = Saboteur::ConstantSubjectFinder.new.call(file).subjects.first
    subject.consumer_lines = consumer_lines
    subject
  end

  it "selects the tests that executed any read of the constant, across files" do
    app = File.join(@root, "app.rb")
    other = File.join(@root, "other.rb")
    subject = constant_subject(app => [3, 9], other => [2])
    map = described_class.new(lines: { app => { 3 => %w[t2], 9 => %w[t1] }, other => { 2 => %w[t3] } },
                              tests: %w[t1 t2 t3])
    expect(map.tests_for(subject)).to eq(%w[t1 t2 t3])
  end

  it "ignores edit lines: reads decide the tests, not the literal's own line" do
    app = File.join(@root, "app.rb")
    subject = constant_subject(app => [3])
    map = described_class.new(lines: { app => { 3 => %w[t1] } }, tests: %w[t1 t2])
    expect(map.tests_for_edit(subject, [1])).to eq(%w[t1])
  end

  it "returns nothing when no read was ever covered" do
    app = File.join(@root, "app.rb")
    subject = constant_subject(app => [3])
    map = described_class.new(lines: {}, tests: %w[t1])
    expect(map.tests_for(subject)).to eq([])
  end
end

RSpec.describe Saboteur::Selection::CoverageMap, "constant reads in endless defs (#319)" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  it "falls back to the def's method-call counter when the read has no line coverage" do
    file = File.join(@root, "constants.rb")
    File.write(file, "MAP = { a: 1 }.freeze\n")
    subject = Saboteur::ConstantSubjectFinder.new.call(file).subjects.first
    app = File.join(@root, "app.rb")
    subject.consumer_lines = { app => [2] }
    subject.consumer_defs = { app => [1] }
    map = described_class.new(lines: {}, tests: %w[t1 t2], methods: { app => { 1 => %w[t2] } })
    expect(map.tests_for(subject)).to eq(%w[t2])
  end

  it "returns no fallback tests when the consumer file has no method coverage" do
    file = File.join(@root, "constants.rb")
    File.write(file, "MAP = { a: 1 }.freeze\n")
    subject = Saboteur::ConstantSubjectFinder.new.call(file).subjects.first
    app = File.join(@root, "app.rb")
    subject.consumer_defs = { app => [1] }
    map = described_class.new(lines: {}, tests: %w[t1], methods: {})
    expect(map.tests_for(subject)).to eq([])
  end

  it "ignores a def line missing from the file's method coverage" do
    file = File.join(@root, "constants.rb")
    File.write(file, "MAP = { a: 1 }.freeze\n")
    subject = Saboteur::ConstantSubjectFinder.new.call(file).subjects.first
    app = File.join(@root, "app.rb")
    subject.consumer_defs = { app => [9] }
    map = described_class.new(lines: {}, tests: %w[t1], methods: { app => { 1 => %w[t1] } })
    expect(map.tests_for(subject)).to eq([])
  end

  it "routes a constant's edits to the constant's tests, never the edit lines" do
    file = File.join(@root, "constants.rb")
    File.write(file, "MAP = { a: 1 }.freeze\n")
    subject = Saboteur::ConstantSubjectFinder.new.call(file).subjects.first
    app = File.join(@root, "app.rb")
    subject.consumer_lines = { app => [2] }
    map = described_class.new(lines: { app => { 2 => %w[t2] }, file => { 1 => %w[t1] } }, tests: %w[t1 t2])
    expect(map.tests_for_edit(subject, [1])).to eq(%w[t2])
  end
end

RSpec.describe Saboteur::Selection::CoverageMap, "dependency files (#344)" do
  it "names files a test touched only through method coverage, for endless defs" do
    map = described_class.new(
      lines: { "/a/caller.rb" => { 3 => ["t1"] } },
      methods: { "/a/helper.rb" => { 5 => ["t1"] } },
      tests: ["t1"]
    )
    expect(map.files_for(["t1"])).to eq(["/a/caller.rb", "/a/helper.rb"])
  end

  it "names the files that ran while the app loaded" do
    map = described_class.new(
      lines: { "/a/caller.rb" => { 3 => ["t1"] } },
      load_lines: { "/a/boot.rb" => { 1 => 2 } },
      tests: ["t1"]
    )
    expect(map.boot_files).to eq(["/a/boot.rb"])
  end
end

RSpec.describe Saboteur::Selection::CoverageMap, ".root_prefixes (#353)" do
  it "lists the resolved and the spelled root, each with a trailing slash" do
    Dir.mktmpdir do |target|
      Dir.mktmpdir do |parent|
        link = File.join(parent, "project")
        File.symlink(target, link)
        expect(described_class.root_prefixes(link)).to eq(["#{File.realpath(link)}/", "#{link}/"])
      end
    end
  end

  it "lists one prefix when the root has no symlink component" do
    Dir.mktmpdir do |dir|
      root = File.realpath(dir)
      expect(described_class.root_prefixes(root)).to eq(["#{root}/"])
    end
  end
end
