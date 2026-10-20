# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Engine::RunFingerprint, "validators and reasons" do
  around { |example| Dir.mktmpdir { |root| @root = File.realpath(root) and example.run } }

  def fingerprint(settings = {}, **options)
    described_class.new(config: Saboteur::Config.new(settings, root: @root), **options)
  end

  def write(name, body = "x")
    path = File.join(@root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def entry(**changes)
    { path: "a.rb", kind: "data", state: "missing", sha256: nil, required: false }.merge(changes)
  end

  def rehash(fields)
    value = { format: 1, files: fields[:inventory], settings: fields[:settings_digest],
              runtime: fields[:runtime_digest] }
    fields.merge(digest: Digest::SHA256.hexdigest(JSON.generate(described_class.canonical_value(value))))
  end

  def restore_error(fields)
    described_class.restore_snapshot(rehash(fields))
    nil
  rescue ArgumentError => e
    e.message
  end

  describe "runtime identity and canonical values" do
    it "lists the engine, version, platform, patchlevel and saboteur version" do
      expect(described_class.runtime_identity).to eq(
        engine: RUBY_ENGINE, version: RUBY_VERSION, platform: RUBY_PLATFORM,
        patchlevel: RUBY_PATCHLEVEL, saboteur: Saboteur::VERSION
      )
    end

    it "orders mapping keys and copies strings" do
      expect(described_class.canonical_mapping({ b: 1, "a" => 2 }).keys).to eq(%w[a b])
      text = +"x"
      copy = described_class.canonical_value(text)
      expect(copy).not_to equal(text)
      expect(copy).to be_frozen
    end
  end

  describe "entry validation" do
    it "accepts a well formed entry and rejects each malformed one" do
      expect(described_class.valid_entry?(entry)).to be(true)
      expect(described_class.valid_entry?(entry.merge(extra: 1))).to be(false)
      expect(described_class.valid_entry?(entry.except(:sha256))).to be(false)
      expect(described_class.valid_entry?(entry(path: "a/"))).to be(false)
      expect(described_class.valid_entry?(entry(required: "yes"))).to be(false)
      expect(described_class.valid_entry?(entry(kind: "bogus"))).to be(false)
      expect(described_class.valid_entry?(entry(state: "bogus"))).to be(false)
    end

    it "requires ruby, boot, hook and source_plugin entries to be required" do
      %w[ruby boot hook source_plugin].each do |kind|
        expect(described_class.valid_entry?(entry(kind: kind, required: false))).to be(false), kind
        expect(described_class.valid_entry?(entry(kind: kind, required: true))).to be(true), kind
      end
      expect(described_class.valid_entry?(entry(kind: "extra", required: false))).to be(true)
    end

    it "checks the state against the digest" do
      digest = "a" * 64
      expect(described_class.valid_state?("present", digest)).to be(true)
      expect(described_class.valid_state?("present", nil)).to be(false)
      expect(described_class.valid_state?("present", 7)).to be(false)
      expect(described_class.valid_state?("missing", nil)).to be(true)
      expect(described_class.valid_state?("unreadable", nil)).to be(true)
      expect(described_class.valid_state?("missing", digest)).to be(false)
      expect(described_class.valid_state?("unreadable", digest)).to be(false)
      expect(described_class.valid_state?("bogus", nil)).to be(false)
    end

    it "accepts only normalized relative and external paths" do
      ["a", "a/b", "external:/abs/x"].each { |path| expect(described_class.valid_path?(path)).to be(true), path }
      ["", "a\0b", "a\\b", "a/", "external:rel", "/abs", "a//b", "./a", "a/./b", "a/../b", "..", ".",
       "external:/a/../b", "external:/", "external://a"].each do |path|
        expect(described_class.valid_path?(path)).to be(false), path.inspect
      end
      expect(described_class.valid_path?(nil)).to be(false)
      expect(described_class.valid_path?(7)).to be(false)
    end
  end

  describe "snapshot restore" do
    let(:fields) do
      write("a.rb")
      fingerprint.snapshot.to_h
    end

    it "names the invalid fields, the format and the identity mismatch" do
      expect(restore_error(fields.merge(extra: 1))).to eq("invalid snapshot fields")
      expect(restore_error(fields.except(:issues))).to eq("invalid snapshot fields")
      expect(restore_error(fields.merge(format_version: 2))).to eq("unsupported fingerprint format")
      expect { described_class.restore_snapshot(fields.merge(digest: "b" * 64)) }
        .to raise_error(ArgumentError, "fingerprint identity mismatch")
    end

    it "accepts only sorted, unique string issues" do
      incomplete = fields.merge(complete: false)
      expect(restore_error(incomplete.merge(issues: %w[a b]))).to be_nil
      [%w[b a], %w[a a], [1], "text", nil].each do |issues|
        expect(restore_error(incomplete.merge(issues: issues))).to eq("invalid issues"), issues.inspect
      end
    end

    it "keeps the unsorted check for rehashed inventories" do
      inventory = [entry(path: "b.rb"), entry(path: "a.rb")]
      expect(restore_error(fields.merge(inventory: inventory))).to eq("unsorted inventory")
      expect(restore_error(fields.merge(inventory: inventory.reverse))).to be_nil
    end

    it "refuses a complete snapshot that records a problem, and allows optional gaps" do
      unreadable = entry(kind: "extra", state: "unreadable")
      missing_required = entry(kind: "extra", required: true)
      expect(restore_error(fields.merge(inventory: [unreadable]))).to eq("invalid complete snapshot")
      expect(restore_error(fields.merge(inventory: [missing_required]))).to eq("invalid complete snapshot")
      expect(restore_error(fields.merge(issues: ["x"]))).to eq("invalid complete snapshot")
      expect(restore_error(fields.merge(inventory: [entry]))).to be_nil
      expect(restore_error(fields.merge(inventory: [unreadable], complete: false))).to be_nil
    end
  end

  describe "verification" do
    before { write("a.rb") }

    let(:current) { fingerprint }
    let(:previous) { current.snapshot }

    def pairs(verification)
      verification.changes.map { |change| [change.path, change.reason] }
    end

    it "is unchanged and complete only when both snapshots are complete and match" do
      verdict = current.verify(previous)
      expect([verdict.unchanged, verdict.complete]).to eq([true, true])
      expect(current.verify(previous.with(complete: false)).complete).to be(false)
      expect(current.verify(previous.with(complete: false)).unchanged).to be(false)
      expect(fingerprint({ "json_report" => "a.rb" }).verify(previous).complete).to be(false)
      expect(current.verify(previous.with(format_version: 2)).complete).to be(false)
      expect(current.verify(previous.with(format_version: 2)).unchanged).to be(false)
      other = current.verify(previous.with(digest: "b" * 64))
      expect([other.unchanged, other.complete]).to eq([false, true])
    end

    it "reports settings and runtime changes by name" do
      expect(pairs(current.verify(previous.with(settings_digest: "c" * 64)))).to eq([%w[settings changed]])
      expect(pairs(current.verify(previous.with(runtime_digest: "d" * 64)))).to eq([%w[runtime changed]])
      expect(pairs(current.verify(previous))).to eq([])
    end

    it "tells a changed file from an unreadable one" do
      previous
      write("a.rb", "other")
      expect(pairs(current.verify(previous))).to eq([%w[a.rb changed]])
      allow(Digest::SHA256).to receive(:file).and_raise(Errno::EACCES)
      expect(pairs(current.verify(previous))).to eq([%w[a.rb unreadable]])
    end
  end

  describe "inventory walk" do
    it "skips each configured output file and flags it" do
      %w[json_report html_report score_history].each do |key|
        write("out.rb")
        snapshot = fingerprint({ key => "out.rb" }).snapshot
        expect(snapshot.inventory.map(&:path)).not_to include("out.rb"), key
        expect(snapshot.issues).to eq(["output overlaps input: out.rb"]), key
      end
    end

    it "lists only regular .rb files and names an unreadable directory" do
      FileUtils.mkdir_p(File.join(@root, "d.rb"))
      FileUtils.mkdir_p(File.join(@root, "sub"))
      allow(Dir).to receive(:children).and_call_original
      allow(Dir).to receive(:children).with(File.join(@root, "sub")).and_raise(Errno::EACCES)
      snapshot = fingerprint.snapshot
      expect(snapshot.inventory.map(&:path)).not_to include("d.rb")
      expect(snapshot.issues).to eq(["unreadable directory: sub"])
    end

    it "reports a symlink once and keeps issues sorted" do
      write("spec/fixtures/real.txt")
      File.symlink(File.join(@root, "spec/fixtures/real.txt"), File.join(@root, "spec/fixtures/l.rb"))
      expect(fingerprint.snapshot.issues).to eq(["symlink input: spec/fixtures/l.rb"])
      write("j.rb")
      issues = fingerprint({ "json_report" => "j.rb", "hooks" => ["missing.rb"] }).snapshot.issues
      expect(issues).to eq(["missing required input: missing.rb", "output overlaps input: j.rb",
                            "symlink input: spec/fixtures/l.rb"])
    end
  end

  describe "declared inputs" do
    def boot_paths(settings)
      fingerprint(settings).snapshot.inventory.select { |item| item.kind == "boot" }.map(&:path)
    end

    it "resolves require names the way Ruby would" do
      %w[plain foo.rb thing.txt dup.rb.rb both both.rb].each { |name| write(name) }
      paths = boot_paths("require" => %w[plain foo thing.txt gone gone2.rb dup.rb both])
      expect(paths).to eq(%w[both dup.rb foo.rb gone gone2.rb plain thing.txt])
    end

    it "tracks source plugins but not the builtin source" do
      builtin = fingerprint({ "sources" => ["builtin"] }).snapshot
      expect(builtin.inventory.map(&:kind)).not_to include("source_plugin")
      snapshot = fingerprint({ "sources" => ["builtin", "plug.rb:Klass"] }).snapshot
      plugin = snapshot.inventory.find { |item| item.kind == "source_plugin" }
      expect([plugin.path, plugin.required, plugin.state]).to eq(["plug.rb", true, "missing"])
      expect(snapshot.issues).to eq(["missing required input: plug.rb"])
    end

    it "marks database config reached through a symlinked directory as a symlink input" do
      Dir.mktmpdir do |outside|
        File.write(File.join(outside, "database.yml"), "x")
        File.symlink(File.realpath(outside), File.join(@root, "config"))
        issues = fingerprint.snapshot.issues
        expect(issues).to include("symlink input: config/database.yml")
      end
    end
  end
end
