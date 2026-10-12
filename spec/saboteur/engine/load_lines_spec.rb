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
end
