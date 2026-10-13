# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Saboteur::Execution::Sandbox do
  it "recognizes Linux only" do
    stub_const("RUBY_PLATFORM", "x86_64-linux")
    expect(described_class.linux?).to be(true)
    stub_const("RUBY_PLATFORM", "x86_64-freebsd")
    expect(described_class.linux?).to be(false)
  end

  it "probes the kernel ABI with the create-ruleset version flag" do
    syscall = double("syscall", call: 2)
    stub_const("Saboteur::Execution::Sandbox::SYSCALL", syscall)
    reset_abi_memo
    expect(described_class.abi_version).to eq(2)
    expect(syscall).to have_received(:call).with(444, 0, 0, 1, 0)
    reset_abi_memo
  end

  it "reports ABI 0 when the kernel rejects the probe" do
    stub_const("Saboteur::Execution::Sandbox::SYSCALL", double("syscall", call: -1))
    reset_abi_memo
    expect(described_class.abi_version).to eq(0)
    expect(described_class.available?).to be(false)
    reset_abi_memo
  end

  it "handles exactly the write-side rights this kernel understands" do
    allow(described_class).to receive(:abi_version).and_return(2)
    expect(described_class.rights_mask).to eq(16_370)
    allow(described_class).to receive(:abi_version).and_return(3)
    expect(described_class.rights_mask).to eq(32_754)
  end

  it "builds the ruleset, grants each writable dir and restricts itself" do
    calls = []
    syscall = double("syscall")
    allow(syscall).to receive(:call) do |*args|
      calls << args
      args.first == 444 ? 5 : 0
    end
    stub_const("Saboteur::Execution::Sandbox::SYSCALL", syscall)
    libc = described_class::LibC
    allow(libc).to receive(:open).and_return(10)
    allow(libc).to receive(:close)
    allow(libc).to receive(:prctl).and_return(0)

    described_class.restrict!(writable: ["/project/tmp", "/project/.saboteur"])

    expect(libc).to have_received(:open).with("/project/tmp", 0o10000000)
    expect(libc).to have_received(:open).with("/project/.saboteur", 0o10000000)
    expect(libc).to have_received(:open).with(File::NULL, 0o10000000)
    expect(libc).to have_received(:prctl).with(38, 1, 0, 0, 0)
    expect(calls.last).to eq([446, 5, 0, 0, 0])
    expect(calls.select { |args| args.first == 445 }.size).to eq(3)
  end

  it "knows whether this kernel supports Landlock" do
    expect(described_class.available?).to eq(described_class.abi_version >= 1)
  end

  it "gates newer rights behind the probed ABI" do
    allow(described_class).to receive(:abi_version).and_return(1)
    base = described_class.rights_mask
    expect(base & described_class::REFER).to eq(0)
    allow(described_class).to receive(:abi_version).and_return(2)
    expect(described_class.rights_mask & described_class::REFER).to eq(described_class::REFER)
  end

  it "raises rather than run half-restricted when a writable dir cannot be opened" do
    skip "Landlock unavailable" unless described_class.available?
    expect { described_class.restrict!(writable: ["/nonexistent/saboteur-test"]) }
      .to raise_error(SystemCallError)
  end

  it "makes the project read-only except the writable dirs" do
    skip "Landlock unavailable" unless described_class.available?
    # The fake project must live outside Dir.tmpdir: the system temp dir is
    # granted writable (real test suites rely on it), which would otherwise
    # cover the fake project root too.
    sandbox_parent = File.expand_path("../../../tmp", __dir__)
    FileUtils.mkdir_p(sandbox_parent)
    Dir.mktmpdir("saboteur-sandbox-", sandbox_parent) do |root|
      root = File.realpath(root)
      FileUtils.mkdir_p(File.join(root, "tmp"))
      cache = File.join(root, ".saboteur")
      FileUtils.mkdir_p(cache)
      File.write(File.join(root, "keep.rb"), "original")

      reader, writer = IO.pipe
      pid = fork do
        reader.close
        begin
          described_class.restrict!(writable: [File.join(root, "tmp"), cache, Dir.tmpdir])
        rescue SystemCallError => e
          writer.write(JSON.generate(sandbox_error: "#{e.class}: #{e.message}"))
          writer.close
          exit!(1)
        end
        outcomes = {
          create_in_root: attempt { File.write(File.join(root, "new.rb"), "x") },
          append_in_root: attempt { File.write(File.join(root, "keep.rb"), "x", mode: "a") },
          remove_in_root: attempt { FileUtils.rm(File.join(root, "keep.rb")) },
          write_in_tmp: attempt { File.write(File.join(root, "tmp", "x"), "x") },
          write_in_cache: attempt { File.write(File.join(cache, "y"), "y") },
          write_system_tmp: attempt { File.write(File.join(Dir.tmpdir, "saboteur-sandbox-proof"), "x") },
          write_dev_null: attempt { File.write(File::NULL, "") },
          read_in_root: attempt { File.read(File.join(root, "keep.rb")) }
        }
        writer.write(JSON.generate(outcomes))
        writer.close
        exit!(0)
      end
      writer.close
      outcomes = JSON.parse(reader.read, symbolize_names: true)
      Process.wait(pid)

      expect(outcomes[:sandbox_error]).to be_nil
      expect(outcomes[:create_in_root]).to eq("denied")
      expect(outcomes[:append_in_root]).to eq("denied")
      expect(outcomes[:remove_in_root]).to eq("denied")
      expect(outcomes[:write_in_tmp]).to eq("ok")
      expect(outcomes[:write_in_cache]).to eq("ok")
      expect(outcomes[:write_system_tmp]).to eq("ok")
      expect(outcomes[:write_dev_null]).to eq("ok")
      expect(outcomes[:read_in_root]).to eq("ok")
      expect(File.read(File.join(root, "keep.rb"))).to eq("original")
    end
  end

  def attempt
    yield
    "ok"
  rescue SystemCallError
    "denied"
  end

  def reset_abi_memo
    return unless described_class.instance_variable_defined?(:@abi_version)

    described_class.instance_eval { remove_instance_variable(:@abi_version) }
  end
end
