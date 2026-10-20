# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Selection::TraceRecorder do
  around do |example|
    Dir.mktmpdir do |dir|
      @source = File.join(File.realpath(dir), "traced.rb")
      File.write(@source, "def traced_a\n  1\nend\n\ndef traced_b\n  2\nend\n\n$traced_at_load = 3\n")
      example.run
    end
  end

  let(:recorder) { described_class.new([@source]) }
  let(:reads) { [] }
  let(:snapshots) { [] }
  let(:arms) { { [:if, 0, 5, 2, 8, 5] => { [:then, 1, 6, 4, 6, 10] => 1, [:else, 2, 7, 4, 7, 8] => 0 } } }

  before do
    allow(Coverage).to receive_messages(state: :running, running?: false)
    allow(Saboteur::CoverageReads).to receive(:result) do |**args|
      reads << args
      snapshots.shift || {}
    end
  end

  def branch_snapshot(branches = arms)
    { @source => { lines: [], branches: branches } }
  end

  after do
    recorder.instance_variable_get(:@line_hits).disable
    recorder.instance_variable_get(:@calls).disable
  end

  def run_test(id, spec_file = "spec/a_spec.rb")
    recorder.test_started(id, spec_file)
    yield
    recorder.test_finished(id)
  end

  def lines_of(map, key = :lines)
    map.public_send(key).fetch(@source).transform_values(&:to_a)
  end

  it "is a Recorder" do
    expect(recorder).to be_a(Saboteur::Selection::Recorder)
  end

  it "reads Coverage when it starts and once more each time the spec file changes, and at the result" do
    recorder.start
    run_test("t1", "spec/a_spec.rb") { nil }
    run_test("t2", "spec/a_spec.rb") { nil }
    run_test("t3", "spec/b_spec.rb") { nil }
    recorder.result

    expect(reads.size).to eq(4)
    expect(reads).to all(eq(stop: false, clear: true))
  end

  it "returns the snapshot the start read" do
    snapshots << { "a.rb" => {} }
    expect(recorder.start).to eq("a.rb" => {})
  end

  it "resumes a suspended Coverage when it starts" do
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Coverage).to receive(:resume)
    recorder.start
    expect(Coverage).to have_received(:resume)
  end

  describe "branches" do
    let(:then_arm) { [6, 4, 6, 10] }

    def branch_tests(map)
      map.branches.fetch(@source).to_h { |span, ids| [span, ids.sort] }
    end

    it "credits a branch read at a file change to every test of the file that ran and of the file starting" do
      recorder.start
      run_test("t1", "spec/a_spec.rb") { nil }
      run_test("t2", "spec/a_spec.rb") { nil }
      snapshots << branch_snapshot
      run_test("t3", "spec/b_spec.rb") { nil }
      run_test("t4", "spec/b_spec.rb") { nil }

      expect(branch_tests(recorder.result)).to include(then_arm => %w[t1 t2 t3 t4])
    end

    it "credits the branches the last file ran, read at the result, to that file's tests only" do
      snapshots.replace([{}, {}, {}, branch_snapshot])
      recorder.start
      run_test("t1", "spec/a_spec.rb") { nil }
      run_test("t2", "spec/b_spec.rb") { nil }

      expect(branch_tests(recorder.result)).to include(then_arm => %w[t2])
    end

    it "credits no file before the first test and none after the last" do
      snapshots.replace([{}, branch_snapshot, branch_snapshot, branch_snapshot])
      recorder.start
      run_test("t1", "spec/a_spec.rb") { nil }
      run_test("t2", "spec/b_spec.rb") { nil }
      recorder.result

      expect(recorder.instance_variable_get(:@outside_branches).keys).to eq(%w[spec/a_spec.rb spec/b_spec.rb])
    end

    it "keeps an arm that never ran as evidence, without crediting a test" do
      recorder.start
      run_test("t1", "spec/a_spec.rb") { nil }
      snapshots << branch_snapshot
      recorder.result

      expect(recorder.result.branches.fetch(@source)).to include([6, 4, 6, 10] => ["t1"], [7, 4, 7, 8] => [])
    end

    it "ignores the branches of a file it was not asked for" do
      recorder.start
      run_test("t1", "spec/a_spec.rb") { nil }
      snapshots << { "/elsewhere.rb" => { lines: [], branches: arms } }

      expect(recorder.result.branches).to be_empty
    end

    it "suspends Coverage while it processes a read and resumes it after" do
      allow(Coverage).to receive_messages(running?: true, state: :suspended, suspend: nil, resume: nil)
      recorder.start
      recorder.test_started("t1", "spec/a_spec.rb")

      expect(Coverage).to have_received(:suspend).once
      expect(Coverage).to have_received(:resume).twice
    end

    it "resumes a Coverage the test left suspended, though it suspended nothing itself" do
      allow(Coverage).to receive_messages(running?: false, state: :suspended, resume: nil)
      recorder.test_started("t1", "spec/a_spec.rb")

      expect(Coverage).to have_received(:resume).once
    end

    it "resumes Coverage and both tracers when the read raises" do
      allow(Saboteur::CoverageReads).to receive(:result).and_raise(Saboteur::Error, "boom")
      allow(Coverage).to receive_messages(running?: true, suspend: nil, resume: nil)

      expect { recorder.test_started("t1", "spec/a_spec.rb") }.to raise_error(Saboteur::Error, "boom")
      expect(Coverage).not_to have_received(:resume)
    end
  end

  it "attributes the lines and method a test ran to that test, and none to a test that ran nothing" do
    recorder.start
    load @source
    run_test("t1") { traced_a }
    run_test("t2") { traced_b }
    run_test("t3") { nil }
    map = recorder.result

    expect(lines_of(map)).to include(2 => ["t1"], 6 => ["t2"])
    expect(lines_of(map, :methods)).to include(1 => ["t1"], 5 => ["t2"])
    expect(map.tests).to eq(%w[t1 t2 t3])
    expect(map.branches).to be_empty
  end

  it "credits a line that ran between tests to every test of the next test's file" do
    recorder.start
    load @source
    run_test("t1", "spec/a_spec.rb") { traced_a }
    map = recorder.result

    expect(lines_of(map).fetch(9)).to eq(["t1"])
  end

  it "records the first test that made a file run" do
    recorder.start
    run_test("t1") { load @source }
    run_test("t2") { traced_a }
    map = recorder.result

    expect(map.first_loaders).to eq(@source => "t1")
  end

  it "matches a file loaded through a symlinked directory to its canonical path" do
    link = "#{File.dirname(@source)}-link"
    File.symlink(File.dirname(@source), link)
    recorder.start
    load File.join(link, "traced.rb")
    run_test("t1") { traced_a }
    map = recorder.result

    expect(lines_of(map)).to include(2 => ["t1"])
    expect(lines_of(map, :methods)).to include(1 => ["t1"])
  ensure
    FileUtils.rm_f(link)
  end

  it "keeps out a file that was not asked for" do
    other = File.join(File.dirname(@source), "other.rb")
    File.write(other, "def other_one\n  1\nend\n")
    recorder.start
    load other
    run_test("t1") { other_one }
    map = recorder.result

    expect(map.lines.keys).not_to include(other)
    expect(map.methods.keys).not_to include(other)
  end

  it "pauses both tracers before it drains them, and resumes them after" do
    order = []
    { line_hits: :lines, calls: :calls }.each do |ivar, label|
      tracer = recorder.instance_variable_get(:"@#{ivar}")
      %i[pause drain resume].each do |name|
        allow(tracer).to receive(name).and_wrap_original do |original, *args, **kwargs|
          order << :"#{label}_#{name}"
          original.call(*args, **kwargs)
        end
      end
    end

    recorder.test_started("t1", "spec/a_spec.rb")

    expect(order).to eq(%i[lines_pause calls_pause lines_resume calls_resume] +
                          %i[lines_pause lines_drain calls_pause calls_drain lines_resume calls_resume])
  end

  it "resumes both tracers even when the hit processing raises" do
    line_hits = recorder.instance_variable_get(:@line_hits)
    calls = recorder.instance_variable_get(:@calls)
    allow(calls).to receive(:drain).and_raise("boom")
    allow(line_hits).to receive(:resume).and_call_original
    allow(calls).to receive(:resume).and_call_original

    expect { recorder.test_started("t1", "spec/a_spec.rb") }.to raise_error("boom")
    expect(line_hits).to have_received(:resume).twice
    expect(calls).to have_received(:resume).twice
  end
end
