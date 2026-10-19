# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "timeout"
require "tmpdir"

RSpec.describe Saboteur::Engine::ResumeManifest do
  let(:dir) { File.join(Dir.mktmpdir, "resume") }

  def manifest(identity = "abc")
    described_class.new(directory: dir, identity: identity)
  end

  it "creates the directory and writes format, version and identity on first use" do
    expect(manifest.verify!).to be_nil
    expect(JSON.parse(File.read(File.join(dir, "manifest.json"))))
      .to eq("format" => 1, "version" => Saboteur::VERSION, "identity" => "abc")
  end

  it "leaves no temp file behind" do
    manifest.verify!
    expect(Dir.children(dir)).to eq(["manifest.json"])
  end

  it "accepts the same identity again without rewriting" do
    manifest.verify!
    before = File.mtime(manifest.path)
    expect(manifest.verify!).to be_nil
    expect(File.mtime(manifest.path)).to eq(before)
  end

  it "raises Mismatch naming the path when the identity differs" do
    manifest.verify!
    expect { manifest("other").verify! }
      .to raise_error(described_class::Mismatch, /#{Regexp.escape(manifest.path)}.*inputs changed.*--resume/)
  end

  it "raises Mismatch when the saboteur version differs" do
    manifest.verify!
    stored = JSON.parse(File.read(manifest.path)).merge("version" => "0.0.0")
    File.write(manifest.path, JSON.generate(stored))
    expect { manifest.verify! }.to raise_error(described_class::Mismatch, /inputs changed/)
  end

  def stored(**overrides)
    { "format" => 1, "version" => Saboteur::VERSION, "identity" => "abc" }.merge(overrides.transform_keys(&:to_s))
  end

  def plant(content)
    FileUtils.mkdir_p(dir)
    File.binwrite(manifest.path, content)
  end

  def expect_mismatch(message)
    Timeout.timeout(2) do
      expect { manifest.verify! }.to raise_error(described_class::Mismatch, "#{manifest.path}: #{message}")
    end
  end

  {
    "invalid JSON" => ["{nope", "unreadable manifest"],
    "invalid UTF-8" => ["\xFF\xFE".b, "unreadable manifest"],
    "a non-object" => ["[1]", "unsupported manifest format"],
    "another format" => [JSON.generate("format" => 2, "version" => "x", "identity" => "abc"),
                         "unsupported manifest format"],
    "no format" => [JSON.generate("version" => "x", "identity" => "abc"), "unsupported manifest format"],
    "an extra key" => [JSON.generate("format" => 1, "version" => "x", "identity" => "abc", "more" => 1),
                       "unsupported manifest format"],
    "a non-String identity" => [JSON.generate("format" => 1, "version" => "x", "identity" => 7),
                                "unsupported manifest format"],
    "a non-String version" => [JSON.generate("format" => 1, "version" => ["x"], "identity" => "abc"),
                               "unsupported manifest format"],
    "an over-long identity" => [JSON.generate("format" => 1, "version" => "x", "identity" => "a" * 513),
                                "unsupported manifest format"],
    "invalid UTF-8 inside a string" => [%({"format":1,"version":"x","identity":"\xFF"}).b, "unreadable manifest"],
    "an oversize file" => [%({"format":1,"version":"x","identity":"abc"}#{' ' * 4096}), "manifest too large"]
  }.each do |label, (content, message)|
    it "raises Mismatch for #{label}" do
      plant(content)
      expect_mismatch(message)
    end
  end

  it "accepts an identity of exactly 512 characters" do
    long = "a" * 512
    plant(JSON.generate(stored(identity: long)))
    expect(manifest(long).verify!).to be_nil
  end

  it "accepts a manifest of exactly 4096 bytes" do
    body = JSON.generate(stored)
    plant(body + (" " * (4096 - body.bytesize)))
    expect(manifest.verify!).to be_nil
  end

  it "raises Mismatch without hanging when the manifest is a FIFO" do
    FileUtils.mkdir_p(dir)
    File.mkfifo(manifest.path)
    expect_mismatch("unreadable manifest")
  end

  it "raises Mismatch for a symlink to a valid manifest" do
    FileUtils.mkdir_p(dir)
    target = File.join(dir, "real.json")
    File.write(target, JSON.generate(stored))
    File.symlink(target, manifest.path)
    expect_mismatch("unreadable manifest")
  end

  it "does not read a FIFO that holds a valid manifest" do
    FileUtils.mkdir_p(dir)
    File.mkfifo(manifest.path)
    File.open(manifest.path, File::RDWR) do |writer|
      writer.write(JSON.generate(stored))
      expect_mismatch("unreadable manifest")
    end
  end

  it "refuses to open a symlink even when lstat reports a regular file" do
    FileUtils.mkdir_p(dir)
    target = File.join(dir, "real.json")
    File.write(target, JSON.generate(stored))
    File.symlink(target, manifest.path)
    allow(File).to receive(:lstat).with(manifest.path).and_return(File.stat(target))
    expect_mismatch("unreadable manifest")
  end

  it "opens a FIFO without blocking even when lstat reports a regular file" do
    FileUtils.mkdir_p(dir)
    File.mkfifo(manifest.path)
    allow(File).to receive(:lstat).with(manifest.path).and_return(File.stat(__FILE__))
    expect_mismatch("unreadable manifest")
  end

  it "raises Mismatch for a symlink to /dev/zero" do
    FileUtils.mkdir_p(dir)
    File.symlink("/dev/zero", manifest.path)
    expect_mismatch("unreadable manifest")
  end

  it "raises Mismatch when the manifest path is a directory" do
    FileUtils.mkdir_p(manifest.path)
    expect_mismatch("unreadable manifest")
  end

  it "keeps the first manifest when two runs race to create it" do
    first = manifest("first")
    second = manifest("second")
    original = File.method(:link)
    allow(File).to receive(:link) do |*args|
      allow(File).to receive(:link).and_call_original
      first.verify!
      original.call(*args)
    end
    expect { second.verify! }.to raise_error(described_class::Mismatch, /inputs changed/)
    expect(JSON.parse(File.read(manifest.path))["identity"]).to eq("first")
    expect(Dir.children(dir)).to eq(["manifest.json"])
  end

  it "accepts a racing run with the same identity" do
    original = File.method(:link)
    allow(File).to receive(:link) do |*args|
      allow(File).to receive(:link).and_call_original
      manifest.verify!
      original.call(*args)
    end
    expect(manifest.verify!).to be_nil
    expect(Dir.children(dir)).to eq(["manifest.json"])
  end

  it "removes the temp file and re-raises when the link fails" do
    allow(File).to receive(:link).and_raise(Errno::EACCES)
    expect { manifest.verify! }.to raise_error(Errno::EACCES)
    expect(Dir.children(dir)).to be_empty
  end
end
