# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MethodCalls do
  def probe = :probe

  let(:here) { File.realpath(__FILE__) }

  it "records [line, name] for a called Ruby method in a wanted file, once per drain" do
    calls = described_class.new(Set[here]).enable
    probe
    probe
    calls.disable
    expect(calls.drain.fetch(here).to_a).to eq([[method(:probe).source_location.last, :probe]])
    expect(calls.drain).to be_empty
  end

  it "subscribes to :call events only" do
    allow(TracePoint).to receive(:new).and_call_original
    described_class.new
    expect(TracePoint).to have_received(:new).with(:call)
  end

  it "keeps only the wanted files" do
    calls = described_class.new(Set["/elsewhere.rb"]).enable
    probe
    calls.disable
    expect(calls.drain).to be_empty
  end

  it "records nothing while paused and records again after resume" do
    calls = described_class.new.enable
    calls.pause
    probe
    expect(calls.drain).not_to have_key(here)
    calls.resume
    probe
    calls.disable
    expect(calls.drain.fetch(here).map(&:last)).to include(:probe)
  end

  it "does not record its own calls" do
    own = File.realpath(described_class.instance_method(:pause).source_location.first)
    calls = described_class.new(Set[own]).enable
    calls.pause
    calls.resume
    calls.disable
    expect(calls.drain).to be_empty
  end

  it "canonicalizes paths before matching them" do
    calls = described_class.new(Set[:canon], canonical: ->(_path) { :canon }).enable
    probe
    calls.disable
    expect(calls.drain.values.flat_map(&:to_a)).to include([method(:probe).source_location.last, :probe])
  end

  it "never sends a message to the receiver of a traced call" do
    proxy = Class.new(BasicObject) do
      def method_missing(name, *) = Kernel.raise("proxy received #{name}")
      def respond_to_missing?(*) = true
      undef_method :equal?
      def run = :ran
    end.new
    calls = described_class.new.enable
    result = proxy.run
    calls.disable
    expect(result).to eq(:ran)
  end

  it "returns itself from enable, disable, pause and resume, and disabling a disabled tracer is harmless" do
    calls = described_class.new
    expect(calls.disable).to equal(calls)
    expect(calls.enable).to equal(calls)
    expect(calls.pause).to equal(calls)
    expect(calls.resume).to equal(calls)
    expect(calls.disable).to equal(calls)
  end

  it "stops recording once disabled" do
    calls = described_class.new.enable
    calls.disable
    probe
    expect(calls.drain).not_to have_key(here)
  end

  it "keeps the hits when drained without clearing" do
    calls = described_class.new.enable
    probe
    calls.disable
    kept = calls.drain(clear: false)
    expect(kept).to have_key(here)
    expect(calls.drain).to have_key(here)
    expect(calls.drain).to be_empty
  end

  it "remembers the tracer the executable booted" do
    described_class.instance_variable_set(:@boot, nil)
    expect(described_class.booted).to be_nil
    booted = described_class.boot
    expect(booted).to be_a(described_class)
    expect(described_class.booted).to equal(booted)
    expect(described_class.boot).to equal(booted)
  ensure
    booted&.disable
    described_class.instance_variable_set(:@boot, nil)
  end

  it "treats a path the canonicalizer refuses as not wanted" do
    refusing = ->(_path) { raise ArgumentError, "string contains null byte" }
    calls = described_class.new(Set[here], canonical: refusing).enable
    probe
    calls.disable
    expect(calls.drain).to be_empty
  end

  it "raises a failure inside the tracer at drain time, once, instead of into the traced program" do
    broken = ->(_path) { raise "canonicalizer broke" }
    calls = described_class.new(Set[here], canonical: broken).enable
    expect { probe }.not_to raise_error
    calls.disable
    expect { calls.drain }.to raise_error("canonicalizer broke")
    expect(calls.drain).to be_empty
  end
end
