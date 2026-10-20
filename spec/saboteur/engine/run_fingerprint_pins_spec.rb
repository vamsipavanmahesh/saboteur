# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Engine::RunFingerprint, "exact contracts" do
  around { |example| Dir.mktmpdir { |root| @root = File.realpath(root) and example.run } }

  def fingerprint(settings = {}, **options)
    described_class.new(config: Saboteur::Config.new(settings, root: @root), **options)
  end

  def write(name, body = "x")
    path = File.join(@root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  def rehash(fields)
    value = { format: fields[:format_version], files: fields[:inventory],
              settings: fields[:settings_digest], runtime: fields[:runtime_digest] }
    fields.merge(digest: Digest::SHA256.hexdigest(JSON.generate(described_class.canonical_value(value))))
  end

  describe "identity values" do
    it "normalizes nested arrays and keeps exact error messages" do
      value = described_class.canonical_value([{ b: 1, "a" => [{ c: nil }] }])
      expect(value).to eql([{ "a" => [{ "c" => nil }], "b" => 1 }])
      expect(value).to be_frozen
      expect { described_class.canonical_value(Float::NAN) }
        .to raise_error(ArgumentError, "non-finite identity number")
      expect { described_class.canonical_value(:symbol) }
        .to raise_error(ArgumentError, "unsupported identity value")
      expect { described_class.canonical_mapping({ "a" => 1, 1 => 2 }) }
        .to raise_error(ArgumentError, "invalid identity key")
      expect { described_class.canonical_mapping({ "a" => 1, a: 2 }) }
        .to raise_error(ArgumentError, "duplicate normalized identity key")
    end
  end

  describe "snapshot validation" do
    let(:fields) do
      write("a.rb")
      fingerprint.snapshot.to_h
    end

    it "reports exact messages for field checks" do
      expect { described_class.validate_snapshot_fields(fields.merge(format_version: 2)) }
        .to raise_error(ArgumentError, "unsupported fingerprint format")
      expect { described_class.validate_snapshot_fields(fields.merge(complete: nil)) }
        .to raise_error(ArgumentError, "invalid completeness")
      %i[digest settings_digest runtime_digest].each do |key|
        ["z" * 64, "#{'a' * 64}\nzz", "zz\n#{'a' * 64}"].each do |bad|
          expect { described_class.validate_snapshot_fields(fields.merge(key => bad)) }
            .to raise_error(ArgumentError, "invalid fingerprint digest")
        end
      end
    end

    it "reports duplicate paths that differ in content, and keeps the issues" do
      entry = fields[:inventory].first
      other = entry.merge(kind: "data")
      expect { described_class.restore_snapshot(rehash(fields.merge(inventory: [entry, other]))) }
        .to raise_error(ArgumentError, "duplicate inventory paths")
      restored = described_class.restore_snapshot(fields.merge(complete: false, issues: ["unsafe"]))
      expect(restored.issues).to eq(["unsafe"])
    end

    it "names the error class for malformed snapshots and the invalid entry" do
      expect { described_class.restore_snapshot(fields.merge(inventory: nil)) }
        .to raise_error(ArgumentError, "invalid fingerprint snapshot: NoMethodError")
      expect { described_class.restore_entry(fields[:inventory].first.merge(kind: "bogus")) }
        .to raise_error(ArgumentError, "invalid fingerprint entry")
    end

    it "answers false, not nil, and anchors the digest pattern" do
      expect(described_class.valid_path?("a/")).to be(false)
      digest = "a" * 64
      expect(described_class.valid_state?("present", digest)).to be(true)
      expect(described_class.valid_state?("present", "#{digest}\nzz")).to be(false)
      expect(described_class.valid_state?("present", "zz\n#{digest}")).to be(false)
    end
  end

  describe "inventory" do
    it "keeps data files optional and the first boot role for a doubled path" do
      write("spec/fixtures/a.yml")
      write("both.rb")
      entries = fingerprint({ "require" => ["both.rb"], "hooks" => ["both.rb"] }).snapshot.inventory
      expect(entries.find { |entry| entry.path == "spec/fixtures/a.yml" }.required).to be(false)
      expect(entries.find { |entry| entry.path == "both.rb" }.kind).to eq("boot")
    end

    it "treats a hash extra file without required as required" do
      snapshot = fingerprint({}, extra_files: [{ path: "gone.txt" }]).snapshot
      expect(snapshot.issues).to eq(["missing required input: gone.txt"])
      expect { fingerprint({}, extra_files: [{ path: "gone.txt" }]) }.not_to raise_error
    end

    it "excludes and flags a score history file inside the project" do
      write("hist.rb")
      snapshot = fingerprint({ "score_history" => "hist.rb" }).snapshot
      expect(snapshot.issues).to eq(["output overlaps input: hist.rb"])
      expect(snapshot.inventory.map(&:path)).not_to include("hist.rb")
    end

    it "marks an unreadable input with its exact issue" do
      write("a.rb")
      allow(Digest::SHA256).to receive(:file).and_raise(Errno::EACCES)
      snapshot = fingerprint.snapshot
      expect(snapshot.issues).to eq(["unreadable input: a.rb"])
      expect(snapshot.inventory.find { |item| item.path == "a.rb" }.state).to eq("unreadable")
    end

    it "labels an external sibling of the root as external" do
      sibling = "#{@root}-sib"
      FileUtils.mkdir_p(sibling)
      path = File.join(sibling, "x.rb")
      File.write(path, "x")
      entry = fingerprint({ "require" => [path] }).snapshot.inventory.find { |item| item.kind == "boot" }
      expect(entry.path).to eq("external:#{path}")
    ensure
      FileUtils.rm_rf(sibling)
    end
  end

  describe "cache overlap" do
    it "flags caches inside each protected tree and at the root" do
      { "app/c" => "app/c", "spec/c" => "spec/c", "test" => "test" }.each_key do |dir|
        issues = fingerprint({ "cache_dir" => dir }).snapshot.issues
        expect(issues).to eq(["cache directory overlaps inputs: #{dir}"])
      end
      expect(fingerprint({ "cache_dir" => "." }).snapshot.issues)
        .to eq(["cache directory overlaps inputs: external:#{@root}"])
    end

    it "does not treat a sibling name that shares a prefix as overlap" do
      write("lib/a.rb")
      %w[li lib2/x].each do |dir|
        expect(fingerprint({ "cache_dir" => dir }).snapshot.issues).to eq([])
      end
    end
  end

  describe "changes" do
    it "lists changes in path order, an added path before a changed one" do
      write("b.rb", "one")
      subject_fingerprint = fingerprint
      before = subject_fingerprint.snapshot
      write("b.rb", "two")
      write("a.rb")
      changes = subject_fingerprint.verify(before).changes
      expect(changes.map { |change| [change.path, change.reason] }).to eq([%w[a.rb added], %w[b.rb changed]])
    end
  end
end
