# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "timeout"
require "tmpdir"

RSpec.describe Saboteur::Engine::CoverageInputsSnapshot do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      @cache = File.join(@root, ".saboteur")
      FileUtils.mkdir_p(@cache)
      File.write(File.join(@root, "a.rb"), "1\n")
      example.run
    end
  end

  let(:key) { "c" * 64 }
  let(:target) { described_class.path(@cache, key) }

  def stored(files: [File.join(@root, "a.rb")])
    File.write(described_class.map_path(@cache, key), "{}")
    data = described_class.build(root: @root, files: files, settings: "s", map_key: key, seed: 1)
    described_class.write(@cache, data)
    data
  end

  def latest
    described_class.latest(@cache, @root)
  end

  # A hang is the failure: fail fast instead of stalling the suite.
  def promptly(&block)
    Timeout.timeout(2, &block)
  end

  def tampered
    data = JSON.parse(File.read(target))
    yield data
    File.write(target, JSON.generate(data))
  end

  it "round-trips a written pair and records the runtime identity, root and relative paths" do
    stored
    data = latest

    expect(data.keys.sort).to eq(%w[files format map_digest map_key root runtime seed settings])
    expect(data["seed"]).to eq(1)
    expect(data["files"].keys).to eq(["a.rb"])
    expect(data["files"]["a.rb"]).to eq(Digest::SHA256.hexdigest("1\n"))
    expect(data["map_digest"]).to eq(Digest::SHA256.hexdigest("{}"))
    expect(data["runtime"]).to eq(
      Digest::SHA256.hexdigest(
        JSON.generate(Saboteur::Engine::RunFingerprint.runtime_identity.merge(map_format: Saboteur::Selection::CoverageMap::FORMAT))
      )
    )
  end

  it "records a missing input as false" do
    stored(files: [File.join(@root, "gone.rb")])

    expect(latest["files"]).to eq("gone.rb" => false)
  end

  it "picks the newest valid snapshot and skips a newer invalid one" do
    stored
    older = target
    File.utime(Time.now - 100, Time.now - 100, older)
    other = "d" * 64
    File.write(described_class.path(@cache, other), "not json")

    expect(latest["map_key"]).to eq(key)
    expect(File.mtime(described_class.path(@cache, other))).to be > File.mtime(older)
  end

  it "records a FIFO input as false instead of blocking on it" do
    fifo = File.join(@root, "pipe.rb")
    File.mkfifo(fifo)
    data = promptly { described_class.build(root: @root, files: [fifo], settings: "s", map_key: key, seed: 1) }

    expect(data["files"]).to eq("pipe.rb" => false)
  end

  it "writes no snapshot, and does not block, when the map file is a FIFO" do
    File.mkfifo(described_class.map_path(@cache, key))
    data = described_class.build(root: @root, files: [], settings: "s", map_key: key, seed: 1)
    promptly { described_class.write(@cache, data) }

    expect(File.exist?(target)).to be(false)
  end

  it "removes the temp file when the write is interrupted, and lets the interrupt through" do
    File.write(described_class.map_path(@cache, key), "{}")
    data = described_class.build(root: @root, files: [], settings: "s", map_key: key, seed: 1)
    allow(File).to receive(:rename).and_raise(Interrupt)

    expect { described_class.write(@cache, data) }.to raise_error(Interrupt)
    expect(Dir.children(@cache)).to eq(["coverage-#{key}.json"])
  end

  it "writes through a private 0600 temp file and never follows a planted link at its name (#471)" do
    File.write(described_class.map_path(@cache, key), "{}")
    data = described_class.build(root: @root, files: [], settings: "s", map_key: key, seed: 1)
    victim = File.join(@root, "victim")
    File.write(victim, "keep")
    allow(SecureRandom).to receive(:hex).with(8).and_return("feedface")
    File.symlink(victim, "#{target}.feedface.tmp")

    described_class.write(@cache, data)
    expect(File.read(victim)).to eq("keep")
    expect(File.exist?(target)).to be(false)

    FileUtils.rm_f("#{target}.feedface.tmp")
    modes = []
    allow(File).to receive(:rename).and_wrap_original do |original, from, to|
      modes << (File.stat(from).mode & 0o777)
      original.call(from, to)
    end
    described_class.write(@cache, data)
    expect(modes).to eq([0o600])
  end

  it "opens without following links or blocking, and reads at most the cap plus one byte" do
    stored
    opened = []
    reads = []
    allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
      original.call(*args) do |io|
        next block.call(io) unless args.first == target

        opened << args
        allow(io).to receive(:read).and_wrap_original do |read, *count|
          reads << count
          read.call(*count)
        end
        block.call(io)
      end
    end
    latest

    flags = File::RDONLY | File::NONBLOCK | File::NOFOLLOW
    expect(opened).to eq([[target, flags]])
    expect(reads).to eq([[described_class::MAX_BYTES + 1]])
  end

  it "builds every key, with the map digest left for the write" do
    data = described_class.build(root: @root, files: [], settings: "s", map_key: key, seed: 1)

    expect(data.keys.sort).to eq(described_class::KEYS)
    expect(data["map_digest"]).to be_nil
  end

  it "does not let newer non-snapshot json files crowd out a valid older snapshot" do
    stored
    File.utime(Time.now - 1000, Time.now - 1000, target)
    (described_class::MAX_CANDIDATES + 1).times do |index|
      File.write(File.join(@cache, "coverage-#{index}.json"), "{}")
    end

    expect(latest).not_to be_nil
  end

  it "skips a dangling link at a snapshot name instead of failing" do
    stored
    File.utime(Time.now - 100, Time.now - 100, target)
    File.symlink(File.join(@root, "nowhere.json"), described_class.path(@cache, "e" * 64))

    expect(latest["map_key"]).to eq(key)
  end

  it "reads nothing when the cache directory has no snapshots" do
    expect(latest).to be_nil
  end

  describe "rejects, as unusable, a snapshot that" do
    before { stored }

    it "is larger than the size cap, even when it is otherwise valid JSON" do
      body = File.read(target)
      File.write(target, body + (" " * (described_class::MAX_BYTES + 1 - body.bytesize)))
      expect(latest).to be_nil
    end

    it "accepts one exactly at the size cap" do
      body = File.read(target)
      File.write(target, body + (" " * (described_class::MAX_BYTES - body.bytesize)))
      expect(latest).not_to be_nil
    end

    it "is not a JSON object" do
      File.write(target, "[]")
      expect(latest).to be_nil
    end

    it "has an extra key" do
      tampered { |data| data["extra"] = 1 }
      expect(latest).to be_nil
    end

    it "lacks a key" do
      tampered { |data| data.delete("runtime") }
      expect(latest).to be_nil
    end

    it "has another format number" do
      tampered { |data| data["format"] = 1 }
      expect(latest).to be_nil
    end

    it "has no seed" do
      tampered { |data| data.delete("seed") }
      expect(latest).to be_nil
    end

    [-1, 2**32, "1", 1.5, true, nil].each do |seed|
      it "has the seed #{seed.inspect}, which is not an integer from 0 to 2**32 - 1" do
        tampered { |data| data["seed"] = seed }
        expect(latest).to be_nil
      end
    end

    [0, (2**32) - 1].each do |seed|
      it "has the seed #{seed}, an accepted bound" do
        tampered { |data| data["seed"] = seed }
        expect(latest["seed"]).to eq(seed)
      end
    end

    %w[map_key map_digest root runtime settings].each do |field|
      it "has a #{field} that is not a 64-character hex digest" do
        tampered { |data| data[field] = "xyz" }
        expect(latest).to be_nil
      end
    end

    it "names a different map key than its file name, even with a matching map beside it" do
      File.write(described_class.map_path(@cache, "e" * 64), "{}")
      tampered { |data| data["map_key"] = "e" * 64 }
      expect(latest).to be_nil
    end

    it "names a map key with a path separator" do
      FileUtils.mkdir_p(File.join(@cache, "sub"))
      File.write(File.join(@cache, "coverage-x.json"), "{}")
      File.write(File.join(@cache, "sub", "x.json"), "{}")
      tampered { |data| data["map_key"] = "x/../.." }
      expect(latest).to be_nil
    end

    it "was written for another project root" do
      tampered { |data| data["root"] = "0" * 64 }
      expect(latest).to be_nil
    end

    it "sits next to a map that changed after the pair was written" do
      File.write(described_class.map_path(@cache, key), "{ }")
      expect(latest).to be_nil
    end

    it "sits next to no map at all" do
      File.delete(described_class.map_path(@cache, key))
      expect(latest).to be_nil
    end

    it "has a map_digest of false, as a missing map would produce" do
      File.delete(described_class.map_path(@cache, key))
      tampered { |data| data["map_digest"] = false }
      expect(latest).to be_nil
    end

    it "is a FIFO, whose size reads as 0" do
      File.delete(target)
      File.mkfifo(target)
      expect(promptly { latest }).to be_nil
    end

    it "is a symlink to /dev/zero, whose size reads as 0 and never ends" do
      File.delete(target)
      File.symlink("/dev/zero", target)
      expect(promptly { latest }).to be_nil
    end

    it "is not a regular file according to lstat, even when its content is a valid snapshot" do
      allow(File).to receive(:lstat).and_call_original
      allow(File).to receive(:lstat).with(target).and_return(instance_double(File::Stat, file?: false))
      expect(latest).to be_nil
    end

    it "is empty" do
      File.write(target, "")
      expect(latest).to be_nil
    end

    it "is a symlink to a valid snapshot elsewhere" do
      elsewhere = File.join(@root, "copy.json")
      File.write(elsewhere, File.read(target))
      File.delete(target)
      File.symlink(elsewhere, target)
      expect(latest).to be_nil
    end

    it "sits next to a FIFO where the map should be" do
      File.delete(described_class.map_path(@cache, key))
      File.mkfifo(described_class.map_path(@cache, key))
      expect(promptly { latest }).to be_nil
    end

    it "has a files entry that is not an object" do
      tampered { |data| data["files"] = [] }
      expect(latest).to be_nil
    end

    it "has a file digest that is neither a hex digest nor false" do
      tampered { |data| data["files"]["a.rb"] = "nope" }
      expect(latest).to be_nil
    end

    it "has a file digest of true" do
      tampered { |data| data["files"]["a.rb"] = true }
      expect(latest).to be_nil
    end

    it "has a path longer than the cap" do
      tampered { |data| data["files"]["a" * (described_class::MAX_PATH + 1)] = false }
      expect(latest).to be_nil
    end

    it "accepts a path exactly at the cap" do
      tampered { |data| data["files"]["a" * described_class::MAX_PATH] = false }
      expect(latest).not_to be_nil
    end

    it "has more entries than the cap" do
      stub_const("#{described_class}::MAX_FILES", 1)
      tampered { |data| data["files"]["b.rb"] = false }
      expect(latest).to be_nil
    end

    it "has exactly the capped number of entries" do
      stub_const("#{described_class}::MAX_FILES", 1)
      expect(latest).not_to be_nil
    end
  end

  it "ignores a snapshot with a path that is not valid UTF-8" do
    stored
    File.binwrite(target, File.binread(target).sub("a.rb", "a\xff.rb".b))

    expect(latest).to be_nil
  end

  it "rejects a files table holding a name with invalid encoding, whatever the parser let through" do
    bad = "a\xff.rb".dup.force_encoding(Encoding::UTF_8)

    expect(described_class.files_valid?({ bad => false })).to be(false)
    expect(described_class.files_valid?({ "a.rb" => false })).to be(true)
  end

  # The newer snapshot's key sorts after the older one's, so plain alphabetical
  # order (or oldest first) picks the wrong file.
  it "prefers the newest of two valid snapshots, not the first by name" do
    older = "a" * 64
    newer = "f" * 64
    [older, newer].each do |map_key|
      File.write(described_class.map_path(@cache, map_key), "{}")
      described_class.write(@cache,
                            described_class.build(root: @root, files: [], settings: "s", map_key: map_key, seed: 1))
    end
    File.utime(Time.at(1_000), Time.at(1_000), described_class.path(@cache, older))
    File.utime(Time.at(2_000), Time.at(2_000), described_class.path(@cache, newer))

    expect(latest["map_key"]).to eq(newer)
  end

  it "writes nothing when the map it names is not on disk" do
    data = described_class.build(root: @root, files: [], settings: "s", map_key: key, seed: 1)
    described_class.write(@cache, data)

    expect(Dir.children(@cache)).to eq([])
  end

  it "only looks at the newest MAX_CANDIDATES snapshots" do
    stored
    File.utime(Time.now - 1000, Time.now - 1000, target)
    described_class::MAX_CANDIDATES.times do |index|
      File.write(described_class.path(@cache, index.to_s.rjust(64, "0")), "junk")
    end

    expect(latest).to be_nil
  end
end
