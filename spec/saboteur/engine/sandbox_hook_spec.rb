# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The sandbox hook the engine hands to the runner (#152, hardened in #178):
# a lambda that Landlock-restricts each mutant child, nil when the layer is
# off or the kernel cannot deliver the full claim (with a one-time note,
# not silence). The claim needs Landlock ABI 3 (Linux 6.2+): earlier ABIs
# cannot restrict truncate(), so the run degrades to guard+canary unless
# c.sandbox = "strict", which refuses.
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

  it "builds a restricting lambda when the layer is on and the kernel delivers ABI 3" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    hook = engine_for({}).send(:sandbox_hook)
    expect(hook).to be_a(Proc)
    expect(err.string).to eq("")
    expect(Dir.exist?(File.join(@root, "tmp"))).to be(true)
    expect(Dir.exist?(File.join(@root, ".saboteur"))).to be(true)
  end

  it "hands no hook when the layer is configured off" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    expect(engine_for({ "sandbox" => false }).send(:sandbox_hook)).to be_nil
  end

  it "warns once and hands no hook on a kernel without Landlock" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
    engine = engine_for({})
    expect(engine.send(:sandbox_hook)).to be_nil
    expect(engine.send(:sandbox_hook)).to be_nil
    expect(err.string.scan("lacks Landlock").size).to eq(1)
    expect(err.string).to include("hazard guard and canary only")
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings.size).to eq(1)
    expect(warnings.first).to include("lacks Landlock")
  end

  it "degrades with a one-time note when the kernel's ABI cannot restrict truncate" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(2)
    engine = engine_for({})
    expect(engine.send(:sandbox_hook)).to be_nil
    expect(engine.send(:sandbox_hook)).to be_nil
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings.size).to eq(1)
    expect(warnings.first).to include("ABI is 2")
    expect(warnings.first).to include("truncate()")
    expect(warnings.first).to include("hazard guard and canary only")
  end

  it "refuses to run degraded when sandbox is strict and the ABI falls short" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(2)
    expect { engine_for({ "sandbox" => "strict" }).send(:sandbox_hook) }
      .to raise_error(Saboteur::Error, /strict.*c\.sandbox = true/m)
  end

  it "refuses to run unsandboxed when the probe itself errors" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version)
      .and_raise(SystemCallError.new("landlock_create_ruleset probe", Errno::EPERM::Errno))
    expect { engine_for({}).send(:sandbox_hook) }
      .to raise_error(Saboteur::Error, /probe failed.*c\.sandbox = false/m)
  end

  it "rejects a nonsense sandbox value at config time" do
    expect { Saboteur::Config.new({ "sandbox" => "paranoid" }, root: @root) }
      .to raise_error(Saboteur::ConfigError, /sandbox must be/)
  end

  it "restricts each child to the project tmp, the cache dir and the system temp dir" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(4)
    allow(Saboteur::Execution::Sandbox).to receive(:restrict!)
    hook = engine_for({}).send(:sandbox_hook)
    hook.call([9])
    expect(Saboteur::Execution::Sandbox).to have_received(:restrict!)
      .with(writable: [File.realpath(File.join(@root, "tmp")),
                       File.realpath(File.join(@root, ".saboteur")),
                       File.realpath(Dir.tmpdir)],
            keep_fds: [9])
  end

  it "grants the dirs from c.sandbox_writable too" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(4)
    allow(Saboteur::Execution::Sandbox).to receive(:restrict!)
    hook = engine_for({ "sandbox_writable" => ["db"] }).send(:sandbox_hook)
    hook.call([9])
    expect(Saboteur::Execution::Sandbox).to have_received(:restrict!)
      .with(writable: [File.realpath(File.join(@root, "tmp")),
                       File.realpath(File.join(@root, ".saboteur")),
                       File.realpath(File.join(@root, "db")),
                       File.realpath(Dir.tmpdir)],
            keep_fds: [9])
  end

  it "hands the runner the engine supervisor, the configured seed and the sandbox hook" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
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
