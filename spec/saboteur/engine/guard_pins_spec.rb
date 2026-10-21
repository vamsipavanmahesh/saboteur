# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::EarlyStopRecording, "pins" do
  def distribution(unreached: [], truncated: [], unverified: [])
    instance_double(Saboteur::Engine::Distribution, unreached: unreached, truncated: truncated,
                                                    unverified: unverified)
  end

  def recorder
    Object.new.extend(described_class)
  end

  it "is a no-op when the stop left nothing unreached, truncated or unverified" do
    rec = recorder
    rec.send(:record_early_stop, distribution)
    expect(rec.instance_variable_get(:@early_stop)).to be_nil
  end

  it "records a stop that left anything behind, with the ids" do
    subject = Struct.new(:id).new("Foo#bar")
    rec = recorder
    rec.send(:record_early_stop, distribution(unreached: [subject]))
    stop = rec.instance_variable_get(:@early_stop)
    expect(stop.unreached).to eq(["Foo#bar"])
    expect(stop.truncated).to eq([])
    expect(stop.unverified).to eq([])
  end

  it "calls the reason max_duration when any subject was truncated, even with none unverified" do
    rec = recorder
    expect(rec.send(:stop_reason, distribution(truncated: [["s", 1]]))).to eq("max_duration")
  end

  it "calls the reason max_duration when any check was unverified, even with none truncated" do
    rec = recorder
    expect(rec.send(:stop_reason, distribution(unverified: ["s"]))).to eq("max_duration")
  end

  it "falls back to the run stop reason only when nothing was truncated or unverified" do
    rec = recorder
    rec.instance_variable_set(:@budget_announced, false)
    expect(rec.send(:stop_reason, distribution(unreached: ["s"]))).to eq("fail_fast")
  end
end

RSpec.describe Saboteur::Engine::GatedRun, "report_unmapped pins" do
  let(:diagnostics) { instance_double(Saboteur::Engine::Diagnostics, inform: nil, announce: nil) }
  let(:host) do
    diagnostics = self.diagnostics
    Class.new do
      include Saboteur::Engine::GatedRun

      define_method(:initialize) { @diagnostics = diagnostics }
      define_method(:config) { { "since" => "main" } }
      attr_reader :calls

      def inform_skipped_specs(_guess) = (@calls ||= []) << :skipped
      def stop_or_warn_unmapped(_guess) = (@calls ||= []) << :stop_or_warn
      public :report_unmapped
    end.new
  end

  it "informs the subjectless message with the since ref only when subjectless files exist" do
    guess = instance_double(Saboteur::Engine::TestGuess::Result, subjectless: ["lib/x.rb"],
                                                                 referenced: [],
                                                                 subjectless_message: "the note")
    host.report_unmapped(guess)
    expect(diagnostics).to have_received(:inform).with("the note")
    expect(guess).to have_received(:subjectless_message).with(since: "main")
    expect(host.calls).to eq(%i[skipped stop_or_warn])
  end

  it "says nothing about subjectless files when there are none, and still runs both steps" do
    guess = instance_double(Saboteur::Engine::TestGuess::Result, subjectless: [], referenced: [])
    host.report_unmapped(guess)
    expect(diagnostics).not_to have_received(:inform)
    expect(host.calls).to eq(%i[skipped stop_or_warn])
  end
end

RSpec.describe Saboteur::Engine::CoverageGuard, "resume pins" do
  it "warns with the error class and message when resume fails" do
    diagnostics = instance_double(Saboteur::Engine::Diagnostics, warn: nil)
    guard = described_class.new(diagnostics)
    guard.instance_variable_set(:@was_running, true)
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Coverage).to receive(:resume).and_raise(RuntimeError, "boom")
    guard.resume
    expect(diagnostics).to have_received(:warn).with("coverage resume failed: RuntimeError: boom")
  end
end

RSpec.describe Saboteur::Engine::ShadowComparison, "missing credit pins" do
  def map(**given)
    args = { lines: { "/a.rb" => { 1 => %w[t1 t2] } }, tests: %w[t1 t2] }.merge(given)
    Saboteur::Selection::CoverageMap.new(**args)
  end

  # A missing credit on an earlier line still rules the verdict when a
  # later line matches: the missing flag accumulates, it is not reassigned.
  it "is a mismatch when an earlier line lacks a credit and a later line matches" do
    full = map(lines: { "/a.rb" => { 1 => %w[t1 t2], 2 => %w[t1 t2] } })
    partial = map(lines: { "/a.rb" => { 1 => %w[t1], 2 => %w[t1 t2] } })
    expect(described_class.call(partial, full)).to include(result: :mismatch, match: false)
  end
end
