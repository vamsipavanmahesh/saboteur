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
    # Root fixtures outside Dir.tmpdir: the system temp dir is granted
    # writable, so a fixture under it would trip the effective-write-set
    # warning meant for real checkouts there.
    parent = File.expand_path("../../../tmp/saboteur-hook-fixtures", __dir__)
    FileUtils.mkdir_p(parent)
    Dir.mktmpdir("hook-", parent) do |dir|
      @root = File.realpath(dir)
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
    expect(Dir.exist?(File.join(@root, "tmp"))).to be(false)
    expect(Dir.exist?(File.join(@root, ".saboteur"))).to be(false)
  end

  it "hands no hook when the layer is configured off" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    expect(engine_for({ "sandbox" => false }).send(:sandbox_hook)).to be_nil
  end

  it "warns once and hands no hook on a kernel without Landlock" do
    allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
    engine = engine_for({})
    expect(engine.send(:sandbox_hook)).to be_nil
    expect(engine.send(:sandbox_hook)).to be_nil
    # once, in the report's warnings only - not inform-printed twice (#178)
    expect(err.string).to eq("")
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings.size).to eq(1)
    expect(warnings.first).to include("macOS has no Landlock").and include("hazard guard and canary only")
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

  it "restricts each child to the project tmp and the system temp dir, not the cache dir (#234)" do
    FileUtils.mkdir_p(File.join(@root, "tmp"))
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(4)
    allow(Saboteur::Execution::Sandbox).to receive(:restrict!)
    hook = engine_for({}).send(:sandbox_hook)
    hook.call([9])
    expect(Saboteur::Execution::Sandbox).to have_received(:restrict!)
      .with(writable: [File.realpath(File.join(@root, "tmp")),
                       File.realpath(Dir.tmpdir)],
            keep_fds: [9])
  end

  it "grants the dirs from c.sandbox_writable too" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(4)
    allow(Saboteur::Execution::Sandbox).to receive(:restrict!)
    hook = engine_for({ "sandbox_writable" => ["db"] }).send(:sandbox_hook)
    hook.call([9])
    expect(Saboteur::Execution::Sandbox).to have_received(:restrict!)
      .with(writable: [File.realpath(File.join(@root, "db")),
                       File.realpath(Dir.tmpdir)],
            keep_fds: [9])
  end

  it "grants only the system temp dir, creating nothing, when the project has no tmp dir" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(4)
    allow(Saboteur::Execution::Sandbox).to receive(:restrict!)
    hook = engine_for({}).send(:sandbox_hook)
    hook.call([9])
    expect(Saboteur::Execution::Sandbox).to have_received(:restrict!)
      .with(writable: [File.realpath(Dir.tmpdir)], keep_fds: [9])
    expect(Dir.exist?(File.join(@root, "tmp"))).to be(false)
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
    expect(captured[:canary]).to be_a(Saboteur::Engine::Canary)
    expect(captured[:log_dir]).to include(".saboteur")
  end
  it "warns when a user grant contains the project root" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    engine = engine_for({ "sandbox_writable" => [@root] })
    engine.send(:sandbox_hook)
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    holder = File.realpath(@root)
    expect(warnings.first).to eq(
      "narrow the sandbox grant #{holder} so it no longer contains the project root\n  " \
      "sandbox grant #{holder} contains the project root; mutant children can write the whole tree"
    )
  end

  it "warns when a user grant is a strict ancestor of the project root" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    engine = engine_for({ "sandbox_writable" => [File.dirname(@root)] })
    engine.send(:sandbox_hook)
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings.join).to include("contains the project root")
  end

  it "warns when a user grant contains another granted dir" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    engine = engine_for({ "sandbox_writable" => ["data", "data/nested", "logs"] })
    engine.send(:sandbox_hook)
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    # exactly one: the data grant contains the data/nested grant, and no other pair
    expect(warnings.size).to eq(1)
    action, cause = warnings.first.split("\n  ", 2)
    expect(action).to match(%r{\Adrop the redundant sandbox grant \S+/data/nested\z})
    expect(cause).to match(%r{\Asandbox grant \S+/data contains the granted dir \S+/data/nested; the narrower grant})
    expect(cause).to end_with("; the narrower grant is redundant")
  end

  it "does not warn for user grants that contain neither the root nor another grant" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    engine = engine_for({ "sandbox_writable" => %w[data logs] })
    engine.send(:sandbox_hook)
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings).to be_empty
  end

  it "warns when the checkout sits inside the system temp dir" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    Dir.mktmpdir("saboteur-under-tmp-") do |tmp_root|
      engine = described_class.new(Saboteur::Config.new({}, root: tmp_root), err: err)
      engine.send(:sandbox_hook)
      warnings = engine.instance_variable_get(:@diagnostics).warnings
      expect(warnings.join).to include("contains the project root")
    end
  end

  it "refuses under strict when the effective write set contains the project root" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    Dir.mktmpdir("saboteur-under-tmp-") do |tmp_root|
      engine = described_class.new(Saboteur::Config.new({ "sandbox" => "strict" }, root: tmp_root), err: err)
      expect { engine.send(:sandbox_hook) }.to raise_error(Saboteur::Error) do |error|
        expect(error.message).to start_with("narrow the sandbox grant ")
        expect(error.message).to match(/ so it no longer contains the project root\n  sandbox grant /)
        expect(error.message).to end_with("; mutant children can write the whole tree - " \
                                          'refusing under c.sandbox = "strict"')
      end
    end
  end

  it "treats a grant of / as containing the project root" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    engine = engine_for({ "sandbox_writable" => ["/"] })
    engine.send(:sandbox_hook)
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings.join).to include("contains the project root")
  end

  it "warns when a symlinked tmp resolves to the project root" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    File.symlink(@root, File.join(@root, "tmp"))
    engine = engine_for({})
    engine.send(:sandbox_hook)
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings.join).to include("contains the project root")
  end

  it "does not warn on the built-in grants alone" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    engine = engine_for({})
    engine.send(:sandbox_hook)
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings).to be_empty
  end
end

# c.sandbox = "seatbelt" (the opt-in macOS sandbox, #436): the probe
# decides - confine when Seatbelt truly enforces, degrade to guard+canary
# with a one-time note otherwise; off macOS the value behaves like true.
RSpec.describe Saboteur::Engine, 'sandbox hook with c.sandbox = "seatbelt"' do
  around do |example|
    parent = File.expand_path("../../../tmp/saboteur-hook-fixtures", __dir__)
    FileUtils.mkdir_p(parent)
    Dir.mktmpdir("hook-", parent) do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:err) { StringIO.new }

  def engine_for(settings)
    described_class.new(Saboteur::Config.new(settings, root: @root), err: err)
  end

  before { allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true) }

  it "hands a confining hook when the probe enforces" do
    allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:ok)
    allow(Saboteur::Execution::Seatbelt).to receive(:restrict!)
    hook = engine_for({ "sandbox" => "seatbelt" }).send(:sandbox_hook)
    expect(hook).to be_a(Proc)
    hook.call([3])
    expect(Saboteur::Execution::Seatbelt).to have_received(:restrict!) do |writable:, keep_fds:|
      expect(writable).to include(File.realpath(Dir.tmpdir))
      expect(writable).not_to include(@root)
      expect(keep_fds).to eq([3])
    end
  end

  it "degrades with a one-time note only when macOS lacks Seatbelt" do
    allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:unavailable)
    engine = engine_for({ "sandbox" => "seatbelt" })
    expect(engine.send(:sandbox_hook)).to be_nil
    expect(engine.send(:sandbox_hook)).to be_nil
    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings.size).to eq(1)
    expect(warnings.first).to eq("sandbox is \"seatbelt\" but this macOS lacks Seatbelt; children run with the " \
                                 "hazard guard and canary only\n  " \
                                 "Fix: set c.sandbox = true to use Landlock instead, or c.sandbox = false to opt out")
  end

  # Pinned against the Landlock sibling (#178): a probe that errors or
  # reports success it cannot prove refuses the run - opting into a
  # sandbox must never buy silent confinement theatre.
  it "refuses when the probe errors or its profile does not enforce" do
    prefix = 'sandbox is "seatbelt" but the Seatbelt probe '
    allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:unenforced)
    message = Regexp.escape(prefix + "reported a profile that did not enforce - a macOS update may have changed it " \
                                     "(#436); refusing to run unsandboxed - set c.sandbox = true")
    expect { engine_for({ "sandbox" => "seatbelt" }).send(:sandbox_hook) }.to raise_error(Saboteur::Error, /#{message}/)
    expect { engine_for({ "sandbox" => "seatbelt" }).send(:sandbox_hook) }
      .to raise_error(Saboteur::Error, /or false to opt out/)
    allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:error)
    message = Regexp.escape("#{prefix}failed (error) - #436 tracks the deprecation")
    expect { engine_for({ "sandbox" => "seatbelt" }).send(:sandbox_hook) }.to raise_error(Saboteur::Error, /#{message}/)
  end

  it "keeps the Landlock path on macOS unless the value is exactly seatbelt" do
    allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:ok)
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
    [true, "strict"].each do |value|
      engine = engine_for({ "sandbox" => value })
      if value == "strict"
        expect { engine.send(:sandbox_hook) }.to raise_error(Saboteur::Error, /macOS has no Landlock/)
      else
        expect(engine.send(:sandbox_hook)).to be_nil
      end
    end
    expect(Saboteur::Execution::Seatbelt).not_to have_received(:probe)
  end

  it "accepts the value off macOS and falls through to the Landlock path" do
    allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(false)
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    expect(engine_for({ "sandbox" => "seatbelt" }).send(:sandbox_hook)).to be_a(Proc)
  end

  # On macOS the seatbelt value takes the Seatbelt path even when the
  # kernel could deliver Landlock ABI 3: a probe answer, not a hook.
  it "takes the Seatbelt path on macOS even when Landlock could deliver" do
    allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:unavailable)
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    expect(engine_for({ "sandbox" => "seatbelt" }).send(:sandbox_hook)).to be_nil
  end

  # c.sandbox = true stays on the Landlock path on macOS: the seatbelt
  # dispatch is for the opt-in value only.
  it "keeps c.sandbox = true on the Landlock path on macOS" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    expect(Saboteur::Execution::Seatbelt).not_to receive(:probe)
    expect(engine_for({ "sandbox" => true }).send(:sandbox_hook)).to be_a(Proc)
  end
end
