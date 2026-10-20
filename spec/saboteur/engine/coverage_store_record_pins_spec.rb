# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::CoverageStore, "pins" do
  def build_store(root, integration: nil, hooks: Saboteur::Hooks.new, **settings)
    config = Saboteur::Config.new(settings, root: root)
    integration ||= instance_double(Saboteur::Integration::RSpec, test_files: [], run_all: true)
    described_class.new(config: config, integration: integration, hooks: hooks, supervisor: nil, diagnostics: nil)
  end

  describe "#build" do
    it "refuses to build when Coverage is not suspended, and says what state it is in" do
      Dir.mktmpdir do |root|
        allow(Coverage).to receive(:state).and_return(:running)
        expect { build_store(root).send(:build, []) }.to raise_error(
          Saboteur::Error,
          "Coverage is running; saboteur must set it up before the app loads. " \
          "Run through the saboteur executable and disable SimpleCov for the run."
        )
      end
    end

    it "refuses to build when Coverage cannot report a state at all" do
      Dir.mktmpdir do |root|
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:state).and_return(false)
        allow(Coverage).to receive(:state).and_return(:suspended)
        expect { build_store(root).send(:build, []) }.to raise_error(Saboteur::Error, /\ACoverage is suspended;/)
      end
    end
  end

  describe "#real_directory?" do
    it "treats a path that vanished as a directory, so it is skipped" do
      Dir.mktmpdir do |root|
        store = build_store(root)
        expect(store.send(:real_directory?, File.join(root, "gone"))).to be(true)
        expect(store.send(:real_directory?, root)).to be(true)
        File.write(File.join(root, "a.rb"), "1\n")
        expect(store.send(:real_directory?, File.join(root, "a.rb"))).to be(false)
      end
    end
  end

  describe "#raise_budget_stop" do
    it "names the admitted seconds and the configured phase timeout" do
      Dir.mktmpdir do |root|
        store = build_store(root, "coverage_timeout" => 600)
        expect { store.send(:raise_budget_stop, 12.34) }.to raise_error(
          Saboteur::BudgetPhaseTimeout,
          "the --max-duration budget stopped the coverage map build (admitted 12.3s of the 600.0s phase timeout)"
        )
      end
    end
  end

  describe "#record" do
    let(:recorder) { instance_double(Saboteur::Selection::Recorder, start: nil) }

    before do
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow($stdout).to receive(:sync=)
    end

    it "flushes the suite log, merges stderr into it, runs the after_fork hook and starts the recorder" do
      Dir.mktmpdir do |root|
        hooks = instance_double(Saboteur::Hooks, run: nil)
        store = build_store(root, hooks: hooks)
        allow(store).to receive(:write_map)
        store.send(:record, StringIO.new, ["/root/lib/a.rb"])
        expect($stdout).to have_received(:sync=).with(true)
        expect($stderr).to have_received(:reopen).with($stdout)
        expect(hooks).to have_received(:run).with(:after_fork)
        expect(recorder).to have_received(:start)
      end
    end

    it "reports the error class and message, then exits with status 1" do
      Dir.mktmpdir do |root|
        integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
        allow(integration).to receive(:run_all).and_raise(ArgumentError, "boom")
        store = build_store(root, integration: integration)
        allow(store).to receive(:exit!)
        writer = StringIO.new
        store.send(:record, writer, ["/root/lib/a.rb"])
        expect(JSON.parse(writer.string)).to eq("error" => "ArgumentError: boom")
        expect(store).to have_received(:exit!).with(1)
      end
    end
  end
end
