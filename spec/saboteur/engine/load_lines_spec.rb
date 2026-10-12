# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "boot coverage lines" do
  let(:engine) { described_class.new(Saboteur::Config.new({}), err: StringIO.new) }
  let(:fake_coverage) { Module.new }

  before do
    allow(fake_coverage).to receive(:state).and_return(:suspended)
    allow(fake_coverage).to receive(:result).with(stop: false, clear: false).and_return({})
    stub_const("Coverage", fake_coverage)
  end

  it "keeps only positive counters for included files" do
    file = File.realpath(__FILE__)
    allow(fake_coverage).to receive(:result).and_return(
      file => { lines: [nil, 0, 2, 1] }, "/outside.rb" => { lines: [1] }
    )
    expect(engine.send(:capture_load_lines, [file])).to eq(file => [3, 4])
    expect(engine.send(:capture_load_lines, [])).to eq({})
  end

  it "omits files with no load hits and returns empty outside suspended coverage" do
    file = File.realpath(__FILE__)
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [nil, 0] })
    expect(engine.send(:capture_load_lines, [file])).to eq({})
    allow(fake_coverage).to receive(:state).and_return(:running)
    expect(engine.send(:capture_load_lines, [file])).to eq({})
  end

  it "suspends running coverage before capturing the counters" do
    allow(fake_coverage).to receive(:state).and_return(:running, :suspended)
    expect(fake_coverage).to receive(:suspend).ordered
    expect(fake_coverage).to receive(:result).with(stop: false, clear: false).ordered.and_return({})
    expect(engine.send(:suspend_coverage, [])).to eq({})
  end

  it "does not suspend already suspended coverage" do
    expect(fake_coverage).not_to receive(:suspend)
    expect(engine.send(:suspend_coverage, [])).to eq({})
  end

  it "boots before selecting files and returns the captured load lines" do
    boot = double("boot")
    integration = double("integration")
    expect(boot).to receive(:load_target).ordered.and_return(integration)
    expect(engine.config).to receive(:included_files).ordered.and_return(["a.rb"])
    expect(engine).to receive(:suspend_coverage).with(["a.rb"]).ordered.and_return("a.rb" => [3])
    expect(engine.send(:boot_target, boot)).to eq([integration, ["a.rb"], { "a.rb" => [3] }])
  end
  it "does not read available counters while coverage is running" do
    file = File.realpath(__FILE__)
    allow(fake_coverage).to receive(:state).and_return(:running)
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [1] })
    expect(fake_coverage).not_to receive(:result)
    expect(engine.send(:capture_load_lines, [file])).to eq({})
  end
  it "passes the boot load lines and execution dependencies to the coverage store" do
    target = subjects_in("class WiringTarget\n  def value\n    1\n  end\nend\n").first
    integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
    boot = instance_double(Saboteur::Engine::Boot, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    load_lines = { target.file => [3] }
    allow(engine).to receive(:boot_target).with(boot).and_return([integration, [target.file], load_lines])
    allow(engine).to receive(:select_subjects).with([target.file]).and_return([[target], nil])
    allow(engine).to receive(:check_baseline).with(integration)
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
    store = instance_double(Saboteur::Engine::CoverageStore, fetch: map)
    expect(Saboteur::Engine::CoverageStore).to receive(:new) do |config:, integration:, hooks:, load_lines:,
                                                              supervisor:, diagnostics:|
      expect(config).to equal(engine.config)
      expect(integration.test_files).to eq([])
      expect(hooks).to equal(engine.hooks)
      expect(load_lines).to eq(target.file => [3])
      expect(supervisor).to be_a(Saboteur::Execution::Supervisor)
      expect(diagnostics).to be_a(Saboteur::Engine::Diagnostics)
      store
    end
    allow(engine).to receive(:candidate_lists).and_return([[]])
    expect(engine.call.results).to eq([])
  end
end
