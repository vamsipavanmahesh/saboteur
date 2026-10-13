# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::ExecutionInputs, :fixture do
  let(:env) { { "BUNDLE_GEMFILE" => "/secret/path-123", "PATH" => ENV.fetch("PATH") } }

  def inputs
    repository = @fixture.repository(base: @base)
    bundler = PreflightSupport::ScriptedRunner.new do |argv|
      PreflightSupport::ScriptedRunner.new.result(argv, 0, "Bundler version 2.5.3\n")
    end
    described_class.new(repository: repository, directory: @fixture.directory, env: env, command_runner: bundler)
  end

  before do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("change")
  end

  it "is stable when nothing changed (valid control)" do
    expect(inputs.digest).to eq(inputs.digest)
  end

  it "changes when an ignored lockfile appears or changes" do
    before = inputs.digest
    @fixture.write(".gitignore", "Gemfile.lock\n")
    @fixture.git("add", ".gitignore")
    @fixture.commit("ignore lock")
    @fixture.write("Gemfile.lock", "one\n")
    first = inputs.digest
    @fixture.write("Gemfile.lock", "two\n")
    expect([first, inputs.digest, before].uniq.length).to eq(3)
  end

  it "changes when a relevant environment value changes, without recording the value" do
    first = inputs.digest
    env["BUNDLE_GEMFILE"] = "/other"
    expect(inputs.digest).not_to eq(first)
    expect(JSON.generate(inputs.snapshot)).not_to include("/secret/path-123")
  end

  it "ignores environment variables that are not on the relevant list" do
    first = inputs.digest
    env["UNRELATED_SECRET"] = "x"
    expect(inputs.digest).to eq(first)
  end

  it "changes when a tracked file is edited on disk, even though the committed tree is unchanged" do
    subject_inputs = inputs
    first = subject_inputs.digest
    @fixture.write("a.txt", "edited after commit\n")
    expect(subject_inputs.digest).not_to eq(first)
  end

  it "stops when an ignored input is a directory instead of a file" do
    subject_inputs = inputs
    FileUtils.mkdir_p(File.join(@fixture.directory, "Gemfile.lock"))
    expect { subject_inputs.digest }.to raise_error(Preflight::ExecutionGap, /Gemfile.lock/)
  end

  it "stops when an ignored input is a broken symlink, not treating it as absent" do
    subject_inputs = inputs
    File.symlink("/nonexistent-target", File.join(@fixture.directory, ".rspec-local"))
    expect { subject_inputs.digest }.to raise_error(Preflight::ExecutionGap, /symlink/)
  end

  it "stops when an ignored input exists but cannot be read" do
    subject_inputs = inputs
    path = File.join(@fixture.directory, ".rspec-local")
    File.write(path, "x")
    File.chmod(0o000, path)
    skip "running as root" if File.readable?(path)
    expect { subject_inputs.digest }.to raise_error(Preflight::ExecutionGap)
  end

  it "stops when a tracked symlink leaves the checkout" do
    File.symlink("/etc/hostname", File.join(@fixture.directory, "link"))
    @fixture.git("add", "link")
    @fixture.commit("link")
    expect { inputs.digest }.to raise_error(Preflight::ExecutionGap, /leaves the checkout/)
  end

  it "binds the content a tracked in-checkout symlink resolves to" do
    File.symlink("a.txt", File.join(@fixture.directory, "link"))
    @fixture.git("add", "link")
    @fixture.commit("link")
    subject_inputs = inputs
    first = subject_inputs.digest
    @fixture.write("a.txt", "changed\n")
    expect(subject_inputs.digest).not_to eq(first)
  end

  it "changes when the ruby or bundle executable found on PATH changes" do
    bin = Dir.mktmpdir
    %w[ruby bundle].each { |name| File.write(File.join(bin, name), "one", perm: 0o755) }
    env["PATH"] = bin
    subject_inputs = inputs
    first = subject_inputs.digest
    File.write(File.join(bin, "bundle"), "two")
    expect(subject_inputs.digest).not_to eq(first)
  end

  it "ignores a non-executable decoy earlier on PATH, as the OS does (valid control and negative)" do
    decoy = Dir.mktmpdir
    real = Dir.mktmpdir
    File.write(File.join(decoy, "ruby"), "decoy")
    File.write(File.join(decoy, "bundle"), "decoy")
    %w[ruby bundle].each { |name| File.write(File.join(real, name), "real", perm: 0o755) }
    env["PATH"] = [decoy, real].join(File::PATH_SEPARATOR)
    subject_inputs = inputs
    first = subject_inputs.digest
    File.write(File.join(decoy, "ruby"), "changed decoy")
    expect(subject_inputs.digest).to eq(first)
    File.write(File.join(real, "ruby"), "changed real", perm: 0o755)
    expect(subject_inputs.digest).not_to eq(first)
  end

  it "refuses an empty or relative PATH entry" do
    ["", ".", "relative/bin"].each do |entry|
      env["PATH"] = [entry, ENV.fetch("PATH")].join(File::PATH_SEPARATOR)
      expect { inputs.digest }.to raise_error(Preflight::ExecutionGap, /empty or relative/)
    end
  end

  it "resolves a relative BUNDLE_GEMFILE against the checkout and binds its lockfile" do
    @fixture.write("alt/Gemfile", "gem 'x'\n")
    @fixture.commit("alt gemfile")
    env["BUNDLE_GEMFILE"] = "alt/Gemfile"
    subject_inputs = inputs
    expect(subject_inputs.snapshot[:bundler_files][:gemfile].first).to eq(File.join(File.realpath(@fixture.directory),
                                                                                    "alt/Gemfile"))
  end

  it "stops when an effective Bundler file is a directory or a broken symlink, not treating it as absent" do
    config = File.join(Dir.mktmpdir, "config")
    env["BUNDLE_USER_CONFIG"] = config
    Dir.mkdir(config)
    expect { inputs.digest }.to raise_error(Preflight::ExecutionGap, /not a regular file/)
    Dir.rmdir(config)
    File.symlink("/nonexistent", config)
    expect { inputs.digest }.to raise_error(Preflight::ExecutionGap, /broken symlink/)
  end

  it "changes when the user Bundler config or an external lockfile changes" do
    config = File.join(Dir.mktmpdir, "config")
    env["BUNDLE_USER_CONFIG"] = config
    first = inputs.digest
    File.write(config, "BUNDLE_X: 1")
    expect(inputs.digest).not_to eq(first)
  end

  it "stops when ruby cannot be found on PATH" do
    env["PATH"] = "/nonexistent"
    expect { inputs.digest }.to raise_error(Preflight::ExecutionGap, /not found on PATH/)
  end

  it "changes when the resolved gem set changes" do
    first = inputs.dependency_digest
    changed = PreflightSupport::ScriptedRunner.new { |a| PreflightSupport::ScriptedRunner.new.result(a, 0, "gems 2\n") }
    other = described_class.new(repository: @fixture.repository(base: @base), directory: @fixture.directory,
                                env: env, command_runner: changed)
    expect(other.dependency_digest).not_to eq(first)
  end

  it "includes the Bundler version and gem list in the dependency identity" do
    listing = Digest::SHA256.hexdigest("Bundler version 2.5.3\n")
    expected = Digest::SHA256.hexdigest(JSON.generate(bundler: "Bundler version 2.5.3", bundled_gems: listing))
    expect(inputs.dependency_digest).to eq(expected)
  end

  it "does not run any command while taking the passive identity" do
    scripted = PreflightSupport::ScriptedRunner.new
    described_class.new(repository: @fixture.repository(base: @base), directory: @fixture.directory, env: env,
                        command_runner: scripted).digest
    expect(scripted.calls).to be_empty
  end

  describe "when an input is swapped for a FIFO after the metadata check" do
    # lstat and File.file? say "regular file", the path is a FIFO when it is opened: the open must not block.
    def swap_in_fifo(path)
      regular = File.join(Dir.mktmpdir, "regular")
      File.write(regular, "x")
      File.mkfifo(path)
      real = File.method(:lstat)
      allow(File).to receive(:lstat) { |arg| arg == path ? real.call(regular) : real.call(arg) }
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with(path).and_return(true)
    end

    it "ends a tracked-file read as a bounded gap" do
      subject_inputs = inputs
      swap_in_fifo(File.join(@fixture.directory, "a.txt")) if FileUtils.rm(File.join(@fixture.directory, "a.txt"))
      expect do
        Timeout.timeout(5) do
          subject_inputs.digest
        end
      end.to raise_error(Preflight::ExecutionGap, /not a regular file/)
    end

    it "ends a Bundler config read as a bounded gap" do
      config = File.join(Dir.mktmpdir, "config")
      env["BUNDLE_USER_CONFIG"] = config
      swap_in_fifo(config)
      expect { Timeout.timeout(5) { inputs.digest } }.to raise_error(Preflight::ExecutionGap, /not a regular file/)
    end
  end

  describe "the lockfile that Bundler uses" do
    {
      "gems.rb" => "gems.locked", "Gemfile" => "Gemfile.lock", "custom.rb" => "custom.rb.lock",
      "Other" => "Other.lock"
    }.each do |gemfile, lock|
      it "maps #{gemfile} to #{lock}" do
        env["BUNDLE_GEMFILE"] = gemfile
        files = inputs.snapshot[:bundler_files]
        expect([File.basename(files[:gemfile].first), File.basename(files[:lockfile].first)]).to eq([gemfile, lock])
      end
    end
  end
end
