# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Saboteur::Execution::Seatbelt do
  it "recognizes macOS only" do
    stub_const("RUBY_PLATFORM", "arm64-darwin24")
    expect(described_class.darwin?).to be(true)
    stub_const("RUBY_PLATFORM", "x86_64-linux")
    expect(described_class.darwin?).to be(false)
  end

  describe ".probe" do
    it "answers unsupported off macOS without forking" do
      allow(described_class).to receive(:darwin?).and_return(false)
      expect(described_class).not_to receive(:fork)
      reset_probe_memo
      expect(described_class.probe).to eq(:unsupported_platform)
      expect(described_class.available?).to be(false)
    end

    it "memoizes the verdict so the fork happens once per process" do
      allow(described_class).to receive(:darwin?).and_return(true)
      allow(described_class).to receive(:run_probe).and_return(:ok)
      reset_probe_memo
      2.times { expect(described_class.probe).to eq(:ok) }
      expect(described_class).to have_received(:run_probe).once
    end
  end

  describe ".classify" do
    it "reads the probe child's verdict word" do
      expect(described_class.classify("ok")).to eq(:ok)
      expect(described_class.classify("unenforced")).to eq(:unenforced)
    end

    it "treats a missing sandbox facility as genuinely unavailable" do
      expect(described_class.classify("init_failed: sandbox_init: Operation not supported")).to eq(:unavailable)
      expect(described_class.classify("init_failed: Function not implemented")).to eq(:unavailable)
    end

    it "fails closed on any other init failure or a lost child" do
      expect(described_class.classify("init_failed: sandbox_init: profile syntax error")).to eq(:error)
      expect(described_class.classify("")).to eq(:error)
    end
  end

  describe "Profile.build" do
    # The Landlock shape mirrored into SBPL: reads, execution, network and
    # IPC stay allowed everywhere (allow default) and only writes are
    # denied outside the grants. A deny-default profile breaks on macOS
    # updates whenever Apple adds a mach service the profile did not name.
    it "allows everything but writes, then re-allows the grants and /dev/null" do
      profile = described_class::Profile.build(writable: ["/proj/tmp", "/tmp"])
      expect(profile).to eq(
        "(version 1)\n" \
        "(allow default)\n" \
        "(deny file-write*)\n" \
        "(allow file-write* (subpath \"/proj/tmp\"))\n" \
        "(allow file-write* (subpath \"/tmp\"))\n" \
        "(allow file-write* (literal \"/dev/null\"))\n"
      )
    end

    it "grants only /dev/null without user dirs" do
      profile = described_class::Profile.build(writable: [])
      expect(profile).to include("(deny file-write*)")
      expect(profile).to include('(allow file-write* (literal "/dev/null"))')
      expect(profile).not_to include("subpath")
    end

    it "escapes quotes and backslashes so a grant cannot break out of its literal" do
      profile = described_class::Profile.build(writable: ['/proj/evil")(allow file-write* (subpath "/'])
      expect(profile).to include('(subpath "/proj/evil\\")(allow file-write* (subpath \\"/")')
      expect(profile.scan(/^\(/).size).to eq(profile.scan(/^\((allow|deny|version)/).size)
    end
  end

  def reset_probe_memo
    return unless described_class.instance_variable_defined?(:@probe)

    described_class.instance_eval { remove_instance_variable(:@probe) }
  end
end

RSpec.describe Saboteur::Execution::Seatbelt, ".restrict! and inherited files" do
  it "applies the built profile with grants and the inherited child logs as literals" do
    fn = double("sandbox_init", call: 0)
    allow(described_class::LibSandbox).to receive(:sandbox_init_fn).and_return(fn)
    allow(described_class).to receive(:fd_paths).and_return(["/run/.saboteur/logs/child-1.log"])
    expect(described_class.restrict!(writable: ["/proj/tmp"], keep_fds: [7])).to be_nil
    expect(fn).to have_received(:call) do |profile, flags, _errbuf|
      expect(profile).to include("(deny file-write*)")
      expect(profile).to include('(subpath "/proj/tmp")')
      expect(profile).to include('(literal "/run/.saboteur/logs/child-1.log")')
      expect(flags).to eq(0)
    end
  end

  it "fails closed: a refused profile means the mutant never runs" do
    fn = double("sandbox_init")
    allow(fn).to receive(:call).and_return(-1)
    allow(described_class::LibSandbox).to receive(:sandbox_init_fn).and_return(fn)
    expect { described_class.restrict!(writable: [], keep_fds: []) }
      .to raise_error(Saboteur::Error, /Seatbelt/)
  end

  it "skips inherited descriptors fcntl cannot map back to a path" do
    fn = double("fcntl")
    allow(fn).to receive(:call).and_return(-1)
    allow(described_class::LibSystem).to receive(:fcntl_fn).and_return(fn)
    expect(described_class.fd_paths([9, 10])).to eq([])
    expect(fn).to have_received(:call).twice
  end
end
