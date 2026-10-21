# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::SandboxPolicy, "pins" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let!(:base) { File.realpath(Dir.mktmpdir) }
  let!(:system_tmp) { File.realpath(Dir.mktmpdir) }
  let(:root) { File.join(base, "proj") }
  let(:gap2) { "this kernel's Landlock ABI is 2 but ABI 3 (Linux 6.2+) is needed to restrict truncate()" }

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

  describe "#sandbox_writable_dirs" do
    it "grants the existing project tmp, each user dir and the system temp dir, as real paths, in that order" do
      FileUtils.mkdir_p(File.join(root, "tmp"))
      dirs = policy("sandbox_writable" => %w[db log]).sandbox_writable_dirs
      expect(dirs).to eq([File.join(root, "tmp"), File.join(root, "db"), File.join(root, "log"), system_tmp])
    end

    it "creates the user dirs under the project root but never makes the project tmp" do
      dirs = policy("sandbox_writable" => ["db"]).sandbox_writable_dirs
      expect(File.directory?(File.join(root, "db"))).to be(true)
      expect(File.exist?(File.join(root, "tmp"))).to be(false)
      expect(dirs).to eq([File.join(root, "db"), system_tmp])
    end

    it "lists a dir granted twice once" do
      dirs = policy("sandbox_writable" => ["db", "./db"]).sandbox_writable_dirs
      expect(dirs).to eq([File.join(root, "db"), system_tmp])
    end

    it "resolves a symlinked grant to its real path" do
      FileUtils.mkdir_p(File.join(root, "real"))
      File.symlink(File.join(root, "real"), File.join(root, "link"))
      expect(policy("sandbox_writable" => ["link"]).sandbox_writable_dirs).to eq([File.join(root, "real"), system_tmp])
    end
  end

  describe "the write set check" do
    it "says nothing when no grant contains the project root or another grant" do
      policy("sandbox_writable" => %w[db log]).sandbox_writable_dirs
      expect(diagnostics.warnings).to be_empty
    end

    it "warns with the exact two-line message when a grant contains the project root" do
      policy("sandbox_writable" => [".."]).sandbox_writable_dirs
      expect(diagnostics.warnings).to eq(
        ["narrow the sandbox grant #{base} so it no longer contains the project root\n  " \
         "sandbox grant #{base} contains the project root; mutant children can write the whole tree"]
      )
    end

    it "warns for a grant that is exactly the project root" do
      policy("sandbox_writable" => ["."]).sandbox_writable_dirs
      expect(diagnostics.warnings.size).to eq(1)
      expect(diagnostics.warnings.first).to start_with("narrow the sandbox grant #{root} so it")
    end

    it "refuses under strict, with the same message and the strict suffix, and does not warn" do
      expect { policy("sandbox" => "strict", "sandbox_writable" => [".."]).sandbox_writable_dirs }
        .to raise_error(Saboteur::Error,
                        "narrow the sandbox grant #{base} so it no longer contains the project root\n  " \
                        "sandbox grant #{base} contains the project root; mutant children can write the whole tree " \
                        '- refusing under c.sandbox = "strict"')
      expect(diagnostics.warnings).to be_empty
    end

    it "only warns when the sandbox is on but not strict" do
      expect { policy("sandbox" => true, "sandbox_writable" => [".."]).sandbox_writable_dirs }.not_to raise_error
      expect(diagnostics.warnings.size).to eq(1)
    end

    it "warns that a grant is redundant when another grant already contains it" do
      policy("sandbox_writable" => ["db", "db/cache"]).sandbox_writable_dirs
      expect(diagnostics.warnings).to eq(
        ["drop the redundant sandbox grant #{File.join(root, 'db', 'cache')}\n  " \
         "sandbox grant #{File.join(root, 'db')} contains the granted dir #{File.join(root, 'db', 'cache')}; " \
         "the narrower grant is redundant"]
      )
    end
  end

  describe "the write set check with symlinks" do
    it "warns when the project tmp is a symlink to a dir that contains the project root" do
      File.symlink(base, File.join(root, "tmp"))
      policy.sandbox_writable_dirs
      expect(diagnostics.warnings.size).to eq(1)
      expect(diagnostics.warnings.first).to start_with("narrow the sandbox grant #{base} so it no longer contains")
    end

    it "compares a symlinked user grant by its real path when looking for redundant grants" do
      FileUtils.mkdir_p(File.join(root, "real", "sub"))
      File.symlink(File.join(root, "real"), File.join(root, "link"))
      policy("sandbox_writable" => %w[link real/sub]).sandbox_writable_dirs
      expect(diagnostics.warnings).to eq(
        ["drop the redundant sandbox grant #{File.join(root, 'real', 'sub')}\n  " \
         "sandbox grant #{File.join(root, 'real')} contains the granted dir #{File.join(root, 'real', 'sub')}; " \
         "the narrower grant is redundant"]
      )
    end
  end

  describe "#path_contains?" do
    it "treats the filesystem root as containing every path, itself included" do
      expect(policy.path_contains?("/", "/any/where")).to be(true)
      expect(policy.path_contains?("/", "/")).to be(true)
    end

    it "contains a path equal to it or below it" do
      expect(policy.path_contains?("/a", "/a")).to be(true)
      expect(policy.path_contains?("/a", "/a/b/c")).to be(true)
    end

    it "does not contain a sibling that only shares a name prefix, or an unrelated path" do
      expect(policy.path_contains?("/a", "/ab")).to be(false)
      expect(policy.path_contains?("/a", "/b")).to be(false)
      expect(policy.path_contains?("/a/b", "/a")).to be(false)
    end
  end

  describe "#hook" do
    it "gives no hook when the sandbox is off, whatever the kernel offers" do
      expect(policy("sandbox" => false).hook).to be_nil
    end

    it "restricts with the user and system dirs when the kernel has ABI 3" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
      hook = policy("sandbox" => true, "sandbox_writable" => ["db"]).hook
      expect(Saboteur::Execution::Sandbox).to receive(:restrict!)
        .with(writable: [File.join(root, "db"), system_tmp], keep_fds: [7])
      hook.call([7])
    end

    it "degrades with one exact note when the kernel is older, and gives no hook" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(2)
      subject_policy = policy("sandbox" => true)
      expect(subject_policy.hook).to be_nil
      expect(subject_policy.hook).to be_nil
      expect(diagnostics.warnings).to eq(
        ["sandbox is on but #{gap2}; children run with the hazard guard and canary only\n  " \
         "Fix: run on Linux 6.2+ (Landlock ABI 3) for full confinement, or set c.sandbox = false to run unsandboxed"]
      )
    end

    it "refuses under strict on an older kernel, naming the gap and the ways out" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(2)
      expect { policy("sandbox" => "strict").hook }.to raise_error(
        Saboteur::Error,
        "sandbox is strict but #{gap2}; refusing to run without the promised sandbox - " \
        "set c.sandbox = true to run degraded, or false to opt out"
      )
    end

    it "refuses and keeps the probe's own error text when the Landlock probe fails" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_raise(Errno::EPERM)
      expect { policy("sandbox" => true).hook }.to raise_error(
        Saboteur::Error,
        "sandbox is on but the Landlock probe failed (#{Errno::EPERM.new.message}); refusing to run " \
        "unsandboxed - set c.sandbox = false to proceed without it"
      )
    end

    it "names the Landlock gap by ABI" do
      expect(described_class.sandbox_gap(2)).to eq(gap2)
      expect(described_class.sandbox_gap(0)).to eq("this kernel lacks Landlock (needs Linux 6.2+)")
    end
  end

  describe "#seatbelt_hook" do
    before do
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
    end

    it "restricts with the user and system dirs when the probe enforces" do
      allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:ok)
      hook = policy("sandbox" => "seatbelt", "sandbox_writable" => ["db"]).hook
      expect(Saboteur::Execution::Seatbelt).to receive(:restrict!)
        .with(writable: [File.join(root, "db"), system_tmp], keep_fds: [9])
      hook.call([9])
    end

    it "gives the unavailable note once, however many times the hook is asked" do
      allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:unavailable)
      seatbelt = policy("sandbox" => "seatbelt")
      2.times { expect(seatbelt.hook).to be_nil }
      expect(diagnostics.warnings).to eq(
        ["sandbox is \"seatbelt\" but this macOS lacks Seatbelt; children run with the hazard guard and " \
         "canary only\n  Fix: set c.sandbox = true to use Landlock instead, or c.sandbox = false to opt out"]
      )
    end
  end
end
