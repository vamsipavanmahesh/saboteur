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
      allow(Digest::SHA256).to receive(:file).with(File.realpath(path)).and_raise(Errno::EACCES)
      current = fingerprint.snapshot
      expect(current.complete).to be(false)
      expect(fingerprint.verify(previous).unchanged).to be(false)
      expect(current.inventory.find { |entry| entry.path == "helper.rb" }.state).to eq("unreadable")
    end
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "evidence contract" do
  it "round trips JSON and verifies an optional missing config file" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({}, root: root)
      fingerprint = described_class.new(config: config, extra_files: [{ path: "config/saboteur.rb", required: false }])
      snapshot = fingerprint.snapshot
      expect(snapshot.complete).to be(true)
      restored = described_class.restore_snapshot(JSON.parse(JSON.generate(snapshot.to_h)))
      expect(restored).to eq(snapshot)
      expect(fingerprint.verify(restored).unchanged).to be(true)
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config", "saboteur.rb"), "Saboteur.configure { |c| c.seed = 2 }\n")
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

RSpec.describe Saboteur::Engine::RunFingerprint, "canonical boundaries" do
  it "uses the same root through checkout aliases and still detects unsafe cache overlap" do
    Dir.mktmpdir do |directory|
      root = File.join(directory, "project")
      FileUtils.mkdir_p(File.join(root, ".saboteur"))
      File.write(File.join(root, ".saboteur/generated.rb"), "1")
      alias_path = File.join(directory, "alias")
      File.symlink(root, alias_path)
      direct = described_class.new(config: Saboteur::Config.new({}, root: root)).snapshot
      aliased = described_class.new(config: Saboteur::Config.new({}, root: alias_path)).snapshot
      expect(aliased).to eq(direct)
      bad = described_class.new(config: Saboteur::Config.new({ "cache_dir" => "lib" }, root: alias_path)).snapshot
      expect(bad.complete).to be(false)
    end
  end

  it "keeps output and cache locations out of settings identity" do
    Dir.mktmpdir do |root|
      first = described_class.new(config: Saboteur::Config.new({}, root: root)).snapshot
      config = Saboteur::Config.new({ "cache_dir" => "other-cache", "json_report" => "other.json" }, root: root)
      second = described_class.new(config: config).snapshot
      expect(first.settings_digest).to eq(second.settings_digest)
      expect(first.digest).to eq(second.digest)
    end
  end

  it "rejects invalid entry paths, kinds and state/hash combinations" do
    digest = "a" * 64
    [{ path: "../app.rb", kind: "ruby", state: "present", sha256: digest },
     { path: "/app.rb", kind: "ruby", state: "present", sha256: digest },
     { path: "a//b.rb", kind: "ruby", state: "present", sha256: digest },
     { path: "app.rb", kind: "unknown", state: "present", sha256: digest },
     { path: "app.rb", kind: "ruby", state: "present", sha256: nil },
     { path: "app.rb", kind: "ruby", state: "missing", sha256: digest }].each do |entry|
      expect { described_class.restore_entry(entry) }.to raise_error(ArgumentError)
    end
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "strict input contracts" do
  it "never lets optional extras override required hooks" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({ "hooks" => ["missing.rb"] }, root: root)
      snapshot = described_class.new(config: config,
                                     extra_files: [{ path: "missing.rb", required: false }]).snapshot
      expect(snapshot.complete).to be(false)
      expect(snapshot.inventory.find { |entry| entry.path == "missing.rb" }.kind).to eq("hook")
    end
  end

  it "refuses output aliases for fixed manifests" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({ "json_report" => "Gemfile" }, root: root)
      expect(described_class.new(config: config).snapshot.issues).to include("output overlaps input: Gemfile")
    end
  end

  it "rejects normalized key collisions and non-JSON runtime identities" do
    [{ x: 1, "x" => 2 }, { x: Object.new }, { x: Float::INFINITY }].each do |identity|
      expect { described_class.canonical_value(identity) }.to raise_error(ArgumentError)
    end
  end

  it "rejects unsorted issue records and complete snapshots containing unreadable entries" do
    Dir.mktmpdir do |root|
      original = described_class.new(config: Saboteur::Config.new({}, root: root)).snapshot.to_h
      expect { described_class.restore_snapshot(original.merge(complete: false, issues: %w[z a])) }
        .to raise_error(ArgumentError)
      inventory = original[:inventory].map(&:dup)
      inventory.first.merge!(state: "unreadable", sha256: nil)
      modified = original.merge(inventory: inventory)
      expect { described_class.restore_snapshot(modified) }.to raise_error(ArgumentError)
    end
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "artifact completeness" do
  it "refuses report directories and descendant source cache directories" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib/generated"))
      File.write(File.join(root, "lib/generated/app.rb"), "1")
      [{ "json_report" => "lib" }, { "html_report" => "lib" }, { "cache_dir" => "lib/generated" }].each do |settings|
        snapshot = described_class.new(config: Saboteur::Config.new(settings, root: root)).snapshot
        expect(snapshot.complete).to be(false)
      end
    end
  end

  it "rejects a distinct explicit checkout root" do
    Dir.mktmpdir do |root|
      Dir.mktmpdir do |other|
        expect { described_class.new(config: Saboteur::Config.new({}, root: root), root: other) }
          .to raise_error(ArgumentError, /root differs/)
      end
    end
  end

  it "rejects a rehashed complete snapshot with a missing required extra" do
    Dir.mktmpdir do |root|
      snapshot = described_class.new(config: Saboteur::Config.new({}, root: root), extra_files: ["missing"]).snapshot
      expect { described_class.restore_snapshot(snapshot.to_h.merge(complete: true, issues: [])) }
        .to raise_error(ArgumentError, /invalid complete/)
    end
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "evidence key schema" do
  it "rejects normalized duplicate keys and extra snapshot fields" do
    Dir.mktmpdir do |root|
      fields = described_class.new(config: Saboteur::Config.new({}, root: root)).snapshot.to_h
      expect { described_class.restore_snapshot(fields.merge("digest" => fields[:digest])) }
        .to raise_error(ArgumentError)
      expect { described_class.restore_snapshot(fields.merge(unknown: 1)) }.to raise_error(ArgumentError)
      entry = fields[:inventory].first
      expect { described_class.restore_entry(entry.merge("path" => entry[:path])) }.to raise_error(ArgumentError)
      expect { described_class.restore_entry(entry.merge(kind: "hook", required: false)) }.to raise_error(ArgumentError)
    end
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "Rails data inputs" do
  around do |example|
    Dir.mktmpdir do |root|
      @root = File.realpath(root)
      FileUtils.mkdir_p(File.join(@root, "spec/fixtures"))
      example.run
    end
  end

  let(:config) { Saboteur::Config.new({}, root: @root) }
  let(:fingerprint) { described_class.new(config: config, runtime_identity: { ruby: "test" }) }

  it "records fixtures as data entries and detects an edit" do
    path = File.join(@root, "spec/fixtures/users.yml")
    File.write(path, "a: 1\n")
    snapshot = fingerprint.snapshot
    expect(snapshot.inventory.find { |e| e.path == "spec/fixtures/users.yml" }.kind).to eq("data")
    File.write(path, "a: 2\n")
    expect(fingerprint.verify(snapshot).changes.map(&:path)).to include("spec/fixtures/users.yml")
  end

  it "detects a schema dump edit and a deleted fixture" do
    FileUtils.mkdir_p(File.join(@root, "db"))
    File.write(File.join(@root, "db/structure.sql"), "1")
    File.write(File.join(@root, "spec/fixtures/a.yml"), "1")
    snapshot = fingerprint.snapshot
    File.write(File.join(@root, "db/structure.sql"), "2")
    File.delete(File.join(@root, "spec/fixtures/a.yml"))
    changes = fingerprint.verify(snapshot).changes
    expect(changes.map(&:path)).to include("db/structure.sql", "spec/fixtures/a.yml")
    expect(changes.map(&:reason)).to include("removed")
  end

  it "round-trips a snapshot containing data entries" do
    File.write(File.join(@root, "spec/fixtures/a.yml"), "1")
    snapshot = fingerprint.snapshot
    restored = described_class.restore_snapshot(JSON.parse(JSON.generate(snapshot.to_h)))
    expect(restored.digest).to eq(snapshot.digest)
  end

  describe "data inputs and run outputs" do
    def issues_for(settings)
      described_class.new(config: Saboteur::Config.new(settings, root: @root)).snapshot
    end

    it "marks the snapshot incomplete when a report would overwrite a declared data input" do
      %w[db/structure.sql config/database.yml spec/fixtures/users.yml test/fixtures/users.yml].each do |path|
        snapshot = issues_for("json_report" => path)
        expect(snapshot.complete).to be(false), path
        expect(snapshot.issues).to include("output overlaps input: #{path}")
      end
    end

    it "treats a not-yet-existing fixture path as an input too" do
      expect(issues_for("html_report" => "test/fixtures/new/report.html").complete).to be(false)
    end

    it "flags a report that matches a fingerprint_extra glob" do
      snapshot = issues_for("json_report" => "data/out.csv", "fingerprint_extra" => ["data/*.csv"])
      expect(snapshot.issues).to include("output overlaps input: data/out.csv")
    end

    it "marks the snapshot incomplete when the cache directory is or contains data inputs" do
      File.write(File.join(@root, "spec/fixtures/users.yml"), "a: 1\n")
      FileUtils.mkdir_p(File.join(@root, "test/fixtures"))
      File.write(File.join(@root, "test/fixtures/users.yml"), "a: 1\n")
      ["test/fixtures", "spec/fixtures", "test/fixtures/cache", "db/structure.sql"].each do |cache|
        snapshot = issues_for("cache_dir" => cache)
        expect(snapshot.complete).to be(false), cache
        expect(snapshot.issues).to include("cache directory overlaps inputs: #{cache}")
      end
    end

    it "keeps Ruby files that are also data inputs (db/schema.rb) as ruby entries" do
      FileUtils.mkdir_p(File.join(@root, "db"))
      File.write(File.join(@root, "db/schema.rb"), "1\n")
      File.write(File.join(@root, "spec/fixtures/users.yml"), "a: 1\n")
      kinds = issues_for({}).inventory.to_h { |entry| [entry.path, entry.kind] }
      expect(kinds).to include("db/schema.rb" => "ruby", "spec/fixtures/users.yml" => "data")
    end

    it "rejects a cache directory that contains existing data inputs outside the fixture trees" do
      FileUtils.mkdir_p(File.join(@root, "config"))
      File.write(File.join(@root, "config/database.yml"), "x: 1\n")
      FileUtils.mkdir_p(File.join(@root, "db"))
      File.write(File.join(@root, "db/structure.sql"), "1")
      FileUtils.mkdir_p(File.join(@root, "data"))
      File.write(File.join(@root, "data/seed.csv"), "1")
      %w[config db].each do |cache|
        expect(issues_for("cache_dir" => cache).issues).to include("cache directory overlaps inputs: #{cache}")
      end
      extra = issues_for("cache_dir" => "data", "fingerprint_extra" => ["data/*.csv"])
      expect(extra.issues).to include("cache directory overlaps inputs: data")
      expect(issues_for("cache_dir" => "data").issues).to eq([])
    end

    it "marks the snapshot incomplete for data reached through a symlinked file, even if the walk skips it" do
      File.write(File.join(@root, "input.csv"), "1")
      FileUtils.mkdir_p(File.join(@root, "vendor"))
      File.symlink(File.join(@root, "input.csv"), File.join(@root, "vendor/input.csv"))
      snapshot = issues_for("fingerprint_extra" => ["vendor/*.csv"], "json_report" => "input.csv")
      expect(snapshot.complete).to be(false)
      expect(snapshot.issues).to include("symlink input: vendor/input.csv")
      expect(snapshot.inventory.map(&:path)).not_to include("vendor/input.csv")
    end

    it "marks the snapshot incomplete for a fixture symlinked to a file outside the project" do
      Dir.mktmpdir do |outside|
        File.write(File.join(outside, "ext.yml"), "a: 1\n")
        File.symlink(File.join(outside, "ext.yml"), File.join(@root, "spec/fixtures/ext.yml"))
        snapshot = issues_for({})
        expect(snapshot.complete).to be(false)
        expect(snapshot.issues).to include("symlink input: spec/fixtures/ext.yml")
      end
    end

    it "marks the snapshot incomplete for data under a symlinked directory" do
      Dir.mktmpdir do |outside|
        FileUtils.mkdir_p(File.join(outside, "set"))
        File.write(File.join(outside, "set/a.csv"), "1")
        File.symlink(File.join(outside, "set"), File.join(@root, "linked"))
        snapshot = issues_for("fingerprint_extra" => ["linked/*.csv"])
        expect(snapshot.issues).to include("symlink input: linked/a.csv")
      end
    end

    it "stays complete for the default cache and report locations" do
      File.write(File.join(@root, "spec/fixtures/users.yml"), "a: 1\n")
      expect(issues_for({}).complete).to be(true)
    end
  end
end
