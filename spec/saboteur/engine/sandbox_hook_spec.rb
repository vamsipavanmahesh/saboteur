# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The sandbox hook the engine hands to the runner (#152): a lambda that
# Landlock-restricts each mutant child, nil when the layer is off or the
# kernel cannot provide it (with a one-time note, not silence).
RSpec.describe Saboteur::Engine, "sandbox hook" do
  around do |example|
    Dir.mktmpdir("saboteur-sandbox-hook-") do |dir|
      @root = dir
      example.run
    end
  end

  let(:err) { StringIO.new }

  def engine_for(settings)
    described_class.new(Saboteur::Config.new(settings, root: @root), err: err)
  end

  it "builds a restricting lambda when the layer is on and the kernel supports it" do
    allow(Saboteur::Execution::Sandbox).to receive(:available?).and_return(true)
    hook = engine_for({}).send(:sandbox_hook)
    expect(hook).to be_a(Proc)
    expect(err.string).to eq("")
    expect(Dir.exist?(File.join(@root, "tmp"))).to be(true)
    expect(Dir.exist?(File.join(@root, ".saboteur"))).to be(true)
  end

  it "hands no hook when the layer is configured off" do
    allow(Saboteur::Execution::Sandbox).to receive(:available?).and_return(true)
    expect(engine_for({ "sandbox" => false }).send(:sandbox_hook)).to be_nil
  end

  it "warns once and hands no hook on a kernel without Landlock" do
    allow(Saboteur::Execution::Sandbox).to receive(:available?).and_return(false)
    engine = engine_for({})
    expect(engine.send(:sandbox_hook)).to be_nil
    expect(engine.send(:sandbox_hook)).to be_nil
    expect(err.string.scan("Landlock").size).to eq(1)
    expect(err.string).to include("hazard guard and canary only")
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings.size).to eq(1)
    expect(warnings.first).to include("Landlock")
  end

  it "restricts each child to the project tmp, the cache dir and the system temp dir" do
    allow(Saboteur::Execution::Sandbox).to receive(:available?).and_return(true)
    allow(Saboteur::Execution::Sandbox).to receive(:restrict!)
    hook = engine_for({}).send(:sandbox_hook)
    hook.call
    expect(Saboteur::Execution::Sandbox).to have_received(:restrict!)
      .with(writable: [File.realpath(File.join(@root, "tmp")),
                       File.realpath(File.join(@root, ".saboteur")),
                       File.realpath(Dir.tmpdir)])
  end

  it "hands the runner the engine supervisor, the configured seed and the sandbox hook" do
    allow(Saboteur::Execution::Sandbox).to receive(:available?).and_return(true)
    engine = engine_for({ "seed" => 7 })
    captured = nil
    runner = Object.new
    allow(Saboteur::Execution::Runner).to receive(:new) do |**kwargs|
      captured = kwargs
      runner
    end
    engine.send(:scheduler_for, nil, Object.new, nil)
    expect(captured[:supervisor]).to be_a(Saboteur::Execution::Supervisor)
    expect(captured[:seed]).to eq(7)
    expect(captured[:sandbox]).to be_a(Proc)
    expect(captured[:log_dir]).to include(".saboteur")
  end
end
