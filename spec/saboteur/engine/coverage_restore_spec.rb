# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# An in-process Engine#call must not leak its coverage suspension into the
# host process (#254): a host that embeds the engine in a Coverage-measured
# process (the dogfood's own coverage-map build is one) records zero hits
# for everything it runs afterwards.
RSpec.describe Saboteur::Engine, "coverage state restore" do
  around do |example|
    Dir.mktmpdir("saboteur-covrestore-") { |dir| @root = File.realpath(dir) and example.run }
  end

  def engine_call(selection: instance_double(Saboteur::Engine::SubjectSelection, select: [], behavior_lines: nil))
    boot = instance_double(Saboteur::Engine::Boot, load_target: double("integration", test_files: []), rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
    described_class.new(Saboteur::Config.new({}, root: @root), err: StringIO.new).call
  end

  # A faithful Coverage stand-in: suspend and resume flip the state, so the
  # engine's own state checks see what a real host would see.
  def fake_coverage(initial)
    state = initial
    allow(Coverage).to receive(:state) { state }
    allow(Coverage).to receive(:suspend) { state = :suspended }
    allow(Coverage).to receive(:resume) { state = :running }
    allow(Coverage).to receive(:result).and_return({})
  end

  it "resumes the host coverage it suspended when the run returns" do
    fake_coverage(:running)
    engine_call
    expect(Coverage).to have_received(:resume)
  end

  it "resumes the host coverage it suspended when the run raises" do
    fake_coverage(:running)
    selection = instance_double(Saboteur::Engine::SubjectSelection)
    allow(selection).to receive(:select).and_raise(Saboteur::Error, "boom")
    expect { engine_call(selection: selection) }.to raise_error(Saboteur::Error, "boom")
    expect(Coverage).to have_received(:resume)
  end

  it "leaves coverage alone when the host was not measuring" do
    fake_coverage(:suspended)
    engine_call
    expect(Coverage).not_to have_received(:resume)
  end

  # The host resumed its own coverage while the engine ran: resuming again
  # would raise and is not the engine's suspension to lift (#254).
  it "does not resume when the host already resumed coverage itself" do
    state = :running
    allow(Coverage).to receive(:state) { state }
    allow(Coverage).to receive(:suspend) { state = :suspended }
    allow(Coverage).to receive(:resume) { state = :running }
    allow(Coverage).to receive(:result).and_return({})
    selection = instance_double(Saboteur::Engine::SubjectSelection, behavior_lines: nil)
    allow(selection).to receive(:select) do
      state = :running # the host resumes mid-run
      []
    end
    engine_call(selection: selection)
    expect(Coverage).not_to have_received(:resume)
  end

  it "warns instead of failing the run when coverage resume raises" do
    fake_coverage(:running)
    allow(Coverage).to receive(:resume).and_raise(StandardError, "resume boom")
    report = engine_call
    expect(report.warnings.join).to include("coverage resume failed: StandardError: resume boom")
  end

  it "does not let a failing coverage resume mask the run's own error" do
    fake_coverage(:running)
    allow(Coverage).to receive(:resume).and_raise(StandardError, "resume boom")
    selection = instance_double(Saboteur::Engine::SubjectSelection)
    allow(selection).to receive(:select).and_raise(Saboteur::Error, "boom")
    expect { engine_call(selection: selection) }.to raise_error(Saboteur::Error, "boom")
  end
end
