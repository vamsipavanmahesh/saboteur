# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::SandboxPolicy do
  let(:err) { StringIO.new }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }
  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  def policy(config)
    described_class.new(config: Saboteur::Config.new(config), root: root, diagnostics: diagnostics)
  end

  before do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(4)
  end

  describe "#hook with the seatbelt opt-in (#436)" do
    it "pins the complete degraded macOS note, including the explicit opt-out" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
      expect(policy({}).degraded_note(0)).to eq(
        "sandbox is on but macOS has no Landlock; children run with the hazard guard and canary only\n  " \
        'Fix: opt into the macOS sandbox with c.sandbox = "seatbelt" ' \
        "(docs/guides/macos-seatbelt-sandbox.md), or set c.sandbox = false to silence this"
      )
    end

    it "confines with Seatbelt when the opt-in is configured on macOS and the probe enforces" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
      allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:ok)
      hook = policy("sandbox" => "seatbelt").hook
      expect(Saboteur::Execution::Seatbelt).to receive(:restrict!)
      hook.call([])
    end

    it "degrades with a one-time note when this macOS lacks Seatbelt" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
      allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:unavailable)
      expect(policy("sandbox" => "seatbelt").hook).to be_nil
      expect(diagnostics.warnings).to include(
        'sandbox is "seatbelt" but this macOS lacks Seatbelt; ' \
        "children run with the hazard guard and canary only\n  " \
        "Fix: set c.sandbox = true to use Landlock instead, or c.sandbox = false to opt out"
      )
    end

    it "refuses and names the verdict when the probe's profile did not enforce" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
      allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:unenforced)
      message = "the Seatbelt probe reported a profile that did not enforce - a macOS update may have changed it " \
                "(#436); refusing to run unsandboxed - set c.sandbox = true to run with the hazard guard and " \
                "canary only, or false to opt out"
      expect { policy("sandbox" => "seatbelt").seatbelt_hook }
        .to raise_error(Saboteur::Error, Regexp.new(Regexp.escape(message)))
    end

    it "refuses and names the verdict when the probe errors" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
      allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return("sandbox_init: -1")
      expect { policy("sandbox" => "seatbelt").seatbelt_hook }
        .to raise_error(Saboteur::Error, /failed \(sandbox_init: -1\)/)
    end

    it "keeps the Landlock path when the sandbox is on but not the seatbelt opt-in, even on macOS" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
      allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:unavailable)
      hook = policy("sandbox" => true).hook
      expect(hook).not_to be_nil
      expect(Saboteur::Execution::Sandbox).to receive(:restrict!)
      hook.call([])
      expect(diagnostics.warnings.grep(/seatbelt/)).to be_empty
    end

    it "points at the seatbelt opt-in instead of blaming the kernel when macOS has no Landlock (#667)" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
      expect(policy("sandbox" => true).hook).to be_nil
      warning = diagnostics.warnings.find { |line| line.start_with?("sandbox is on") }
      expect(warning).to include("macOS has no Landlock")
      expect(warning).to include('c.sandbox = "seatbelt"')
      expect(warning).to include("docs/guides/macos-seatbelt-sandbox.md")
      expect(warning).not_to include("Linux 6.2+")
    end

    it "keeps the Landlock kernel wording on a Linux kernel without Landlock (#667)" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(false)
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
      expect(policy("sandbox" => true).hook).to be_nil
      expect(diagnostics.warnings).to include("sandbox is on but this kernel lacks Landlock (needs Linux 6.2+); " \
                                              "children run with the hazard guard and canary only\n  " \
                                              "Fix: run on Linux 6.2+ (Landlock ABI 3) for full confinement, " \
                                              "or set c.sandbox = false to run unsandboxed")
    end

    it "keeps the ABI wording on a kernel with Landlock below ABI 3 (#667)" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(2)
      expect(policy("sandbox" => true).hook).to be_nil
      expect(diagnostics.warnings.join).to include("Landlock ABI is 2")
    end

    it "keeps the Landlock path for the seatbelt opt-in off macOS" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(false)
      hook = policy("sandbox" => "seatbelt").hook
      expect(hook).not_to be_nil
      expect(Saboteur::Execution::Sandbox).to receive(:restrict!)
      hook.call([])
    end
  end
end
