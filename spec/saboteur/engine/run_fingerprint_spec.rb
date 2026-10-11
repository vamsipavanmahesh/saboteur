# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Engine::RunFingerprint do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/helper.rb"), "1\n")
      example.run
    end
  end

  let(:config) { Saboteur::Config.new({}, root: @root) }
  let(:fingerprint) { described_class.new(config: config, runtime_identity: { ruby: "test" }) }

  it "returns a deterministic immutable complete snapshot and verifies it" do
    snapshot = fingerprint.snapshot
    expect(snapshot.complete).to be(true)
    expect(snapshot.digest).to eq(fingerprint.snapshot.digest)
    expect(snapshot).to be_frozen
    expect(snapshot.inventory).to be_frozen
    expect(fingerprint.verify(snapshot).unchanged).to be(true)
  end

  it "detects edits outside the selected subject/include and additions, removals and renames" do
    snapshot = fingerprint.snapshot
    File.write(File.join(@root, "lib/helper.rb"), "2\n")
    expect(fingerprint.verify(snapshot).changes.map(&:reason)).to include("changed")
    File.write(File.join(@root, "lib/other.rb"), "3\n")
    expect(fingerprint.verify(snapshot).changes.map(&:reason)).to include("added")
    File.rename(File.join(@root, "lib/helper.rb"), File.join(@root, "lib/renamed.rb"))
    expect(fingerprint.verify(snapshot).changes.map(&:reason)).to include("removed", "added")
  end

  it "includes missing dependency manifests so a new lockfile changes the snapshot" do
    snapshot = fingerprint.snapshot
    expect(snapshot.inventory.find { |entry| entry.path == "Gemfile.lock" }.state).to eq("missing")
    File.write(File.join(@root, "Gemfile.lock"), "lock\n")
    expect(fingerprint.verify(snapshot).unchanged).to be(false)
  end

  it "tracks explicit external boot and extra files without treating missing required files as complete" do
    external = File.join(File.dirname(@root), "external-#{File.basename(@root)}.rb")
    File.write(external, "1\n")
    begin
      configured = Saboteur::Config.new({ "require" => [external], "hooks" => ["missing.rb"] }, root: @root)
      snapshot = described_class.new(config: configured, extra_files: [external]).snapshot
      expect(snapshot.complete).to be(false)
      expect(snapshot.inventory.map(&:path)).to include("external:#{external}", "missing.rb")
    ensure
      FileUtils.rm_f(external)
    end
  end

  it "changes for effective config and runtime identity" do
    original = fingerprint.snapshot
    changed = described_class.new(config: Saboteur::Config.new({ "baseline_timeout" => 7 }, root: @root),
                                  runtime_identity: { ruby: "test" })
    expect(changed.verify(original).unchanged).to be(false)
    other_runtime = described_class.new(config: config, runtime_identity: { ruby: "other" })
    expect(other_runtime.verify(original).unchanged).to be(false)
  end

  it "does not hash generated cache or git contents" do
    before = fingerprint.snapshot
    %w[.saboteur .git].each do |directory|
      FileUtils.mkdir_p(File.join(@root, directory))
      File.write(File.join(@root, directory, "generated.rb"), "changed\n")
    end
    expect(fingerprint.verify(before).unchanged).to be(true)
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "unsafe inputs" do
  it "marks a discovered symlink boundary incomplete rather than claiming a safe snapshot" do
    Dir.mktmpdir do |root|
      File.symlink("/tmp", File.join(root, "external_sources"))
      snapshot = described_class.new(config: Saboteur::Config.new({}, root: root)).snapshot
      expect(snapshot.complete).to be(false)
      expect(snapshot.issues).to include("symlink input: external_sources")
    end
  end

  it "does not allow unreadable content to produce a reusable snapshot" do
    Dir.mktmpdir do |root|
      path = File.join(root, "helper.rb")
      File.write(path, "1")
      fingerprint = described_class.new(config: Saboteur::Config.new({}, root: root))
      previous = fingerprint.snapshot
      allow(Digest::SHA256).to receive(:file).with(path).and_raise(Errno::EACCES)
      current = fingerprint.snapshot
      expect(current.complete).to be(false)
      expect(fingerprint.verify(previous).unchanged).to be(false)
      expect(current.inventory.find { |entry| entry.path == "helper.rb" }.state).to eq("unreadable")
    end
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "evidence contract" do
  it "round trips JSON and verifies an optional missing config marker" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({}, root: root)
      fingerprint = described_class.new(config: config, extra_files: [{ path: ".saboteur.yml", required: false }])
      snapshot = fingerprint.snapshot
      expect(snapshot.complete).to be(true)
      restored = described_class.restore_snapshot(JSON.parse(JSON.generate(snapshot.to_h)))
      expect(restored).to eq(snapshot)
      expect(fingerprint.verify(restored).unchanged).to be(true)
      File.write(File.join(root, ".saboteur.yml"), "seed: 2\n")
      expect(fingerprint.verify(restored).unchanged).to be(false)
      expect { described_class.restore_snapshot({}) }.to raise_error(ArgumentError)
    end
  end

  it "refuses unsafe configured output roots instead of silently dropping application inputs" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({ "cache_dir" => "lib", "json_report" => "spec/a.rb" }, root: root)
      snapshot = described_class.new(config: config).snapshot
      expect(snapshot.complete).to be(false)
      expect(snapshot.issues).to include("cache directory overlaps inputs: lib", "output overlaps input: spec/a.rb")
    end
  end
end
