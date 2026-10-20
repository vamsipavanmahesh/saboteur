# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::SandboxPolicy, "notes" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let!(:base) { File.realpath(Dir.mktmpdir) }
  let!(:system_tmp) { File.realpath(Dir.mktmpdir) }
  let(:root) { File.join(base, "proj") }

  before do
    FileUtils.mkdir_p(root)
    allow(Dir).to receive(:tmpdir).and_return(system_tmp)
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(4)
    allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(false)
  end

  after do
    FileUtils.remove_entry(base)
    FileUtils.remove_entry(system_tmp)
  end

  def policy(config = {})
    described_class.new(config: Saboteur::Config.new(config), root: root, diagnostics: diagnostics)
  end

  it "names macOS, not a kernel, when there is no Landlock on a Mac" do
    allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
    expect(described_class.sandbox_gap(0)).to eq("macOS has no Landlock")
  end

  it "names the kernel when there is no Landlock off a Mac" do
    expect(described_class.sandbox_gap(0)).to eq("this kernel lacks Landlock (needs Linux 6.2+)")
  end

  it "prints a redundant grant's name safely when it holds a control character" do
    name = File.join(root, "db", "x\ny")
    policy("sandbox_writable" => ["db", name]).sandbox_writable_dirs
    safe = Saboteur::Text.display_safe(name)
    expect(safe).not_to eq(name)
    expect(diagnostics.warnings.join).to include("drop the redundant sandbox grant #{safe}\n  ")
    expect(diagnostics.warnings.join).to include("contains the granted dir #{safe}; the narrower grant is redundant")
  end

  it "prints the containing grant's name safely too" do
    outer = File.join(root, "a\nb")
    policy("sandbox_writable" => [outer, File.join(outer, "c")]).sandbox_writable_dirs
    safe = Saboteur::Text.display_safe(outer)
    expect(safe).not_to eq(outer)
    expect(diagnostics.warnings.join).to include("\n  sandbox grant #{safe} contains the granted dir ")
  end

  describe "when a Seatbelt probe refuses the run" do
    before do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
    end

    def refusal(verdict)
      allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(verdict)
      policy("sandbox" => "seatbelt").hook
    end

    it "says the profile did not enforce, with the macOS update hint" do
      expect { refusal(:unenforced) }.to raise_error(
        Saboteur::Error,
        'sandbox is "seatbelt" but the Seatbelt probe reported a profile that did not enforce - ' \
        "a macOS update may have changed it (#436); refusing to run unsandboxed - set c.sandbox = true to run " \
        "with the hazard guard and canary only, or false to opt out"
      )
    end

    it "names any other verdict and points at the deprecation issue" do
      expect { refusal(:errored) }.to raise_error(
        Saboteur::Error,
        'sandbox is "seatbelt" but the Seatbelt probe failed (errored) - #436 tracks the deprecation; ' \
        "refusing to run unsandboxed - set c.sandbox = true to run with the hazard guard and canary only, " \
        "or false to opt out"
      )
    end
  end
end
