# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::LineHits do
  def probe
    :probe
  end

  let(:here) { File.realpath(__FILE__) }
  let(:tracers) { [] }

  after { tracers.each(&:disable) }

  def tracer(*, **)
    described_class.new(*, **).tap { |made| tracers << made }
  end
  let(:probe_line) { method(:probe).source_location.last + 1 }

  it "records the lines that ran in a wanted file, once per drain" do
    hits = tracer(Set[here]).enable
    probe
    probe
    hits.disable
    expect(hits.drain.fetch(here)).to include(probe_line)
    expect(hits.drain).to be_empty
  end

  it "subscribes to :line events only" do
    allow(TracePoint).to receive(:new).and_call_original
    tracer
    expect(TracePoint).to have_received(:new).with(:line)
  end

  it "keeps only the wanted files" do
    hits = tracer(Set["/elsewhere.rb"]).enable
    probe
    hits.disable
    expect(hits.drain).to be_empty
  end

  it "keeps every file when none are given" do
    hits = tracer.enable
    probe
    hits.disable
    expect(hits.drain).to have_key(here)
  end

  it "records nothing while paused and records again after resume" do
    hits = tracer.enable
    hits.pause
    probe
    expect(hits.drain.fetch(here, Set.new)).not_to include(probe_line)
    hits.resume
    probe
    hits.disable
    expect(hits.drain.fetch(here)).to include(probe_line)
  end

  it "canonicalizes paths before matching them" do
    hits = tracer(Set[:canon], canonical: ->(_path) { :canon }).enable
    probe
    hits.disable
    expect(hits.drain.values.flat_map(&:to_a)).to include(probe_line)
  end

  it "returns itself from enable, disable, pause and resume, and disabling a disabled tracer is harmless" do
    hits = tracer
    expect(hits.disable).to equal(hits)
    expect(hits.enable).to equal(hits)
    expect(hits.pause).to equal(hits)
    expect(hits.resume).to equal(hits)
    expect(hits.disable).to equal(hits)
  end

  it "stops recording once disabled" do
    hits = tracer.enable
    hits.disable
    hits.drain
    probe
    expect(hits.drain).to be_empty
  end

  it "keeps the hits when drained without clearing" do
    hits = tracer.enable
    probe
    hits.disable
    expect(hits.drain(clear: false)).to have_key(here)
    expect(hits.drain).to have_key(here)
    expect(hits.drain).to be_empty
  end

  it "treats a path the canonicalizer refuses as not wanted" do
    refusing = ->(_path) { raise ArgumentError, "string contains null byte" }
    hits = tracer(Set[here], canonical: refusing).enable
    probe
    hits.disable
    expect(hits.drain).to be_empty
  end

  it "treats an eval'd file name as not wanted when the canonicalizer cannot resolve it" do
    real = ->(path) { File.realpath(path) }
    hits = tracer(Set[here], canonical: real).enable
    RubyVM::InstructionSequence.compile("1 + 1\n2 + 2", "(eval at spec)").eval
    hits.disable
    expect { hits.drain }.not_to raise_error
    expect(hits.drain.keys - [here]).to be_empty
  end

  it "treats a canonicalizer that returns a bad type as not wanted" do
    hits = tracer(Set[here], canonical: ->(_path) { raise TypeError, "no implicit conversion" }).enable
    probe
    hits.disable
    expect(hits.drain).to be_empty
  end

  it "raises a failure inside the tracer at drain time, once, instead of into the traced program" do
    broken = ->(_path) { raise "canonicalizer broke" }
    hits = tracer(Set[here], canonical: broken).enable
    expect { probe }.not_to raise_error
    hits.disable
    expect { hits.drain }.to raise_error("canonicalizer broke")
    expect(hits.drain).to be_empty
  end

  it "counts a def line and the lines of the branch taken, as Coverage does" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "traced.rb")
      File.write(source, "def traced(flag)\n  if flag\n    1\n  else\n    2\n  end\nend\n")
      hits = tracer(Set[source]).enable
      load source
      Object.new.send(:traced, true)
      hits.disable
      expect(hits.drain.fetch(source).to_a.sort).to eq([1, 2, 3])
    ensure
      Object.send(:remove_method, :traced) if Object.private_method_defined?(:traced)
    end
  end
end
