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
        "children run with the hazard guard and canary only"
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

    it "keeps the Landlock path for the seatbelt opt-in off macOS" do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(false)
      hook = policy("sandbox" => "seatbelt").hook
      expect(hook).not_to be_nil
      expect(Saboteur::Execution::Sandbox).to receive(:restrict!)
      hook.call([])
    end
  end
end
