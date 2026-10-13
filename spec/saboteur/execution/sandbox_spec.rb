# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"

RSpec.describe Saboteur::Execution::Sandbox do
  it "recognizes Linux only" do
    stub_const("RUBY_PLATFORM", "x86_64-linux")
    expect(described_class.linux?).to be(true)
    stub_const("RUBY_PLATFORM", "x86_64-freebsd")
    expect(described_class.linux?).to be(false)
  end

  it "probes the kernel ABI with the create-ruleset version flag" do
    syscall = double("syscall", call: 2)
    allow(described_class::LibC).to receive(:syscall_fn).and_return(syscall)
    reset_abi_memo
    expect(described_class.abi_version).to eq(2)
    expect(syscall).to have_received(:call).with(444, 0, 0, 1, 0)
    reset_abi_memo
  end

  it "reports ABI 0 when the kernel has no Landlock (ENOSYS)" do
    allow(described_class::LibC).to receive(:syscall_fn).and_return(double("syscall", call: -1))
    allow(described_class).to receive(:last_errno).and_return(Errno::ENOSYS::Errno)
    reset_abi_memo
    expect(described_class.abi_version).to eq(0)
    expect(described_class.available?).to be(false)
    reset_abi_memo
  end

  it "reports ABI 0 when the kernel has Landlock disabled (EOPNOTSUPP)" do
    allow(described_class::LibC).to receive(:syscall_fn).and_return(double("syscall", call: -1))
    allow(described_class).to receive(:last_errno).and_return(Errno::EOPNOTSUPP::Errno)
    reset_abi_memo
    expect(described_class.abi_version).to eq(0)
    reset_abi_memo
  end

  it "fails closed when the probe errors for any other reason (EPERM under seccomp)" do
    allow(described_class::LibC).to receive(:syscall_fn).and_return(double("syscall", call: -1))
    allow(described_class).to receive(:last_errno).and_return(Errno::EPERM::Errno)
    reset_abi_memo
    expect { described_class.abi_version }.to raise_error(SystemCallError, /landlock_create_ruleset probe/)
    reset_abi_memo
  end

  it "reads errno as a native int" do
    expect(File.read(File.join(__dir__, "../../../lib/saboteur/execution/sandbox.rb")))
      .to include('unpack1("i")')
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
    open_fn = double("open", call: 10)
    allow(described_class::LibC).to receive(:syscall_fn).and_return(syscall)
    allow(described_class::LibC).to receive(:open_fn).and_return(open_fn)
    allow(described_class::LibC).to receive(:close_fn).and_return(double("close", call: 0))
    allow(described_class::LibC).to receive(:prctl_fn).and_return(double("prctl", call: 0))
    allow(described_class::LibC).to receive(:fcntl_fn).and_return(double("fcntl", call: 0)) # O_RDONLY: close nothing
    allow(described_class).to receive(:last_errno).and_return(0)

    described_class.restrict!(writable: ["/project/tmp", "/project/.saboteur"])

    expect(open_fn).to have_received(:call).with("/project/tmp", 0o10000000)
    expect(open_fn).to have_received(:call).with("/project/.saboteur", 0o10000000)
    expect(open_fn).to have_received(:call).with(File::NULL, 0o10000000)
    expect(described_class::LibC.prctl_fn).to have_received(:call).with(38, 1, 0, 0, 0)
    expect(described_class::LibC.close_fn).to have_received(:call).with(5)
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

  it "closes inherited writable regular files outside the granted dirs before restricting" do
    skip "needs /proc/self/fd" unless described_class.linux?
    Dir.mktmpdir("saboteur-fds-") do |root|
      granted = File.join(root, "tmp")
      sibling = File.join(root, "tmp2") # prefix look-alike: must NOT count as granted
      linked = File.join(root, "link")
      FileUtils.mkdir_p([granted, sibling])
      File.symlink(granted, linked)
      File.write(File.join(root, "project.rb"), "x")
      File.write(File.join(granted, "ok.rb"), "x")
      File.write(File.join(sibling, "sib.rb"), "x")
      File.write(File.join(linked, "via_link.rb"), "x")

      project_io = File.open(File.join(root, "project.rb"), "r+") # rubocop:disable Style/FileOpen
      readonly_io = File.open(File.join(root, "project.rb"), "r") # rubocop:disable Style/FileOpen
      granted_io = File.open(File.join(granted, "ok.rb"), "r+") # rubocop:disable Style/FileOpen
      sibling_io = File.open(File.join(sibling, "sib.rb"), "r+") # rubocop:disable Style/FileOpen
      symlink_io = File.open(File.join(linked, "via_link.rb"), "r+") # rubocop:disable Style/FileOpen
      reader, _writer = IO.pipe

      described_class::InheritedFds.close_writable_files([File.realpath(granted)], [reader.fileno])

      expect(attempt do
        project_io.write("y")
        project_io.flush
      end).to eq("denied")
      expect(attempt do
        sibling_io.write("y")
        sibling_io.flush
      end).to eq("denied")
      expect(readonly_io.read(1)).to eq("x")
      expect(attempt do
        granted_io.write("y")
        granted_io.flush
      end).to eq("ok")
      expect(attempt do
        symlink_io.write("y")
        symlink_io.flush
      end).to eq("ok")
    end
  end

  it "requires without touching libc on a non-Linux platform" do
    lib = File.expand_path("../../../lib", __dir__)
    script = <<~RUBY
      $LOAD_PATH.unshift(#{lib.inspect})
      require "fiddle"
      def Fiddle.dlopen(*) = raise("dlopen called on a non-Linux platform")
      require "fiddle/import"
      module Fiddle
        module ImporterTripwire
          def dlload(*) = raise("dlload called on a non-Linux platform")
        end
        Importer.prepend(ImporterTripwire)
      end
      Object.send(:remove_const, :RUBY_PLATFORM)
      Object.const_set(:RUBY_PLATFORM, "arm64-darwin23")
      require "saboteur/execution/sandbox"
      sandbox = Saboteur::Execution::Sandbox
      unless sandbox.abi_version.zero? && !sandbox.available? && sandbox.rights_mask.is_a?(Integer)
        abort "sandbox not inert on a non-Linux platform"
      end
      puts "inert ok"
    RUBY
    out, status = Open3.capture2e({ "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil },
                                  RbConfig.ruby, "-e", script)
    expect(status).to be_success, "expected a clean inert load, got: #{out}"
    expect(out).to include("inert ok")
  end

  it "raises rather than run half-restricted when a writable dir cannot be opened" do
    skip "Landlock unavailable" unless described_class.available?
    expect { described_class.restrict!(writable: ["/nonexistent/saboteur-test"]) }
      .to raise_error(SystemCallError)
  end

  it "makes the project read-only except the writable dirs, inherited fds included" do
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

      inherited_writer = File.open(File.join(root, "keep.rb"), "a") # rubocop:disable Style/FileOpen
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        begin
          described_class.restrict!(writable: [File.join(root, "tmp"), cache, Dir.tmpdir],
                                    keep_fds: [writer.fileno])
        rescue SystemCallError => e
          writer.write(JSON.generate(sandbox_error: "#{e.class}: #{e.message}"))
          writer.close
          exit!(1)
        end
        outcomes = {
          create_in_root: attempt { File.write(File.join(root, "new.rb"), "x") },
          append_in_root: attempt { File.write(File.join(root, "keep.rb"), "x", mode: "a") },
          truncate_in_root: attempt { File.truncate(File.join(root, "keep.rb"), 0) },
          remove_in_root: attempt { FileUtils.rm(File.join(root, "keep.rb")) },
          inherited_fd_write: attempt do
            inherited_writer.write("x")
            inherited_writer.flush
          end,
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
      inherited_writer.close
      writer.close
      outcomes = JSON.parse(reader.read, symbolize_names: true)
      Process.wait(pid)

      expect(outcomes[:sandbox_error]).to be_nil
      expect(outcomes[:create_in_root]).to eq("denied")
      expect(outcomes[:append_in_root]).to eq("denied")
      expect(outcomes[:remove_in_root]).to eq("denied")
      expect(outcomes[:inherited_fd_write]).to eq("denied")
      expect(outcomes[:write_in_tmp]).to eq("ok")
      expect(outcomes[:write_in_cache]).to eq("ok")
      expect(outcomes[:write_system_tmp]).to eq("ok")
      expect(outcomes[:write_dev_null]).to eq("ok")
      expect(outcomes[:read_in_root]).to eq("ok")
      if described_class.abi_version >= 3
        expect(outcomes[:truncate_in_root]).to eq("denied")
        expect(File.read(File.join(root, "keep.rb"))).to eq("original")
      else
        # ABI < 3 cannot restrict truncate: the file may be emptied.
        expect(outcomes[:truncate_in_root]).to eq("ok")
      end
    end
  end

  def attempt
    yield
    "ok"
  rescue SystemCallError, IOError
    "denied"
  end

  def reset_abi_memo
    return unless described_class.instance_variable_defined?(:@abi_version)

    described_class.instance_eval { remove_instance_variable(:@abi_version) }
  end
end
