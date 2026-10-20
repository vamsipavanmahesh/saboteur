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

  it "reads no Coverage while it starts or records" do
    allow(Coverage).to receive(:result).and_call_original
    recorder.start
    load @source
    run_test("t1") { traced_a }
    recorder.result
    expect(Coverage).not_to have_received(:result)
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

  it "returns an empty snapshot from start, like a Coverage that read nothing" do
    expect(recorder.start).to eq({})
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

    expect(order).to eq(%i[lines_pause lines_drain calls_pause calls_drain lines_resume calls_resume])
  end

  it "resumes both tracers even when the hit processing raises" do
    line_hits = recorder.instance_variable_get(:@line_hits)
    calls = recorder.instance_variable_get(:@calls)
    allow(calls).to receive(:drain).and_raise("boom")
    allow(line_hits).to receive(:resume).and_call_original
    allow(calls).to receive(:resume).and_call_original

    expect { recorder.test_started("t1", "spec/a_spec.rb") }.to raise_error("boom")
    expect(line_hits).to have_received(:resume)
    expect(calls).to have_received(:resume)
  end
end
