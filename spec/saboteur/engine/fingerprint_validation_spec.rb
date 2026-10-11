# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Engine::RunFingerprint, "guard contracts" do
  around { |example| Dir.mktmpdir { |root| @root = root and example.run } }
  let(:fingerprint) { described_class.new(config: Saboteur::Config.new({}, root: @root)) }
  let(:snapshot) { fingerprint.snapshot }

  def rehash(fields)
    value = { format: fields[:format_version], files: fields[:inventory],
              settings: fields[:settings_digest], runtime: fields[:runtime_digest] }
    fields.merge(digest: Digest::SHA256.hexdigest(JSON.generate(described_class.canonical_value(value))))
  end

  it "validates duplicate and unsorted inventory independently of its checksum" do
    fields = snapshot.to_h
    expect { described_class.restore_snapshot(rehash(fields.merge(inventory: fields[:inventory] * 2))) }
      .to raise_error(ArgumentError, /duplicate/)
    expect { described_class.restore_snapshot(rehash(fields.merge(inventory: fields[:inventory].reverse))) }
      .to raise_error(ArgumentError, /unsorted/)
  end

  it "validates all digest fields, format and completeness with otherwise valid evidence" do
    fields = snapshot.to_h
    %i[digest settings_digest runtime_digest].each do |key|
      [nil, "z" * 64, "a" * 63, "a" * 65, "#{'a' * 64}\n", 7].each do |value|
        expect { described_class.restore_snapshot(fields.merge(key => value)) }.to raise_error(ArgumentError)
      end
    end
    expect { described_class.restore_snapshot(fields.merge(format_version: 2)) }.to raise_error(ArgumentError)
    expect { described_class.restore_snapshot(fields.merge(complete: "yes")) }.to raise_error(ArgumentError)
    expect { described_class.restore_snapshot(fields.merge(digest: "b" * 64)) }
      .to raise_error(ArgumentError, /identity mismatch/)
    expect { described_class.restore_snapshot(fields.merge(inventory: nil)) }.to raise_error(ArgumentError)
  end

  it "checks complete implications with correctly rehashed evidence" do
    fields = snapshot.to_h
    inventory = fields[:inventory].map(&:dup)
    inventory.first.merge!(kind: "hook", required: true, state: "missing", sha256: nil)
    invalid = rehash(fields.merge(inventory: inventory))
    expect { described_class.restore_snapshot(invalid) }.to raise_error(ArgumentError, /invalid complete/)
    inventory.first.merge!(kind: "extra", required: false, state: "unreadable")
    expect { described_class.restore_snapshot(rehash(fields.merge(inventory: inventory))) }
      .to raise_error(ArgumentError, /invalid complete/)
    expect { described_class.restore_snapshot(fields.merge(issues: ["unsafe"])) }
      .to raise_error(ArgumentError, /invalid complete/)
    restored = described_class.restore_snapshot(rehash(fields.merge(complete: false, inventory: inventory,
                                                                    issues: ["unsafe"])))
    expect(restored.complete).to be(false)
  end

  it "keeps immutable copies of caller strings, issues and entry hashes" do
    fields = snapshot.to_h
    fields[:digest] = fields[:digest].dup
    fields[:inventory] = fields[:inventory].map do |entry|
      entry.transform_values do |value|
        value.is_a?(String) ? value.dup : value
      end
    end
    restored = described_class.restore_snapshot(fields)
    fields[:digest].replace("b" * 64)
    fields[:inventory].first[:path].replace("changed")
    expect(restored).to eq(snapshot)
    expect(restored.digest).to be_frozen
    expect(restored.inventory.first.path).to be_frozen
    expect(described_class.restore_issues(["a"]).first).to be_frozen
    [nil, "a", [1], %w[a a], %w[b a]].each do |issues|
      expect { described_class.restore_issues(issues) }.to raise_error(ArgumentError)
    end
  end

  it "validates each entry component independently" do
    valid = { path: "lib/a.rb", kind: "ruby", required: true, state: "present", sha256: "a" * 64 }
    expect(described_class.restore_entry(valid).to_h).to eq(valid)
    { path: [nil, "", "a\0b", "a\\b", "a/./b", "a/../b", "a/", "external:relative", "external:/a//b"],
      kind: [nil, "invalid"], required: [nil, 1], state: [nil, "invalid"],
      sha256: [nil, 1, "b" * 63] }.each do |key, values|
      values.each do |value|
        expect do
          described_class.restore_entry(valid.merge(key => value))
        end.to raise_error(ArgumentError)
      end
    end
    expect { described_class.restore_entry(valid.merge(extra: 1)) }.to raise_error(ArgumentError)
    expect { described_class.restore_entry(valid.except(:required)) }.to raise_error(ArgumentError)
    %w[ruby boot hook source_plugin].each do |kind|
      expect { described_class.restore_entry(valid.merge(kind: kind, required: false)) }.to raise_error(ArgumentError)
    end
    %w[missing unreadable].each do |state|
      expect(described_class.restore_entry(valid.merge(state: state, sha256: nil)).state).to eq(state)
      expect { described_class.restore_entry(valid.merge(state: state)) }.to raise_error(ArgumentError)
    end
    expect(described_class.valid_path?("external:/a/b.rb")).to be(true)
    expect(described_class.valid_path?("a:b.rb")).to be(true)
  end

  it "pins runtime metadata and canonical mapping semantics" do
    expect(described_class.runtime_identity).to eq(engine: RUBY_ENGINE, version: RUBY_VERSION, platform: RUBY_PLATFORM,
                                                   patchlevel: RUBY_PATCHLEVEL, saboteur: Saboteur::VERSION)
    expect(described_class.canonical_value({ z: 2, a: [true, false, nil, 1, 1.5] }))
      .to eq({ "a" => [true, false, nil, 1, 1.5], "z" => 2 })
    expect(described_class.canonical_value({ z: 2, a: 1 }).keys).to eq(%w[a z])
    expect(described_class.canonical_value({ a: 1, z: 2 })).to eq(described_class.canonical_value({ z: 2, a: 1 }))
    expect(described_class.canonical_value([1, 2])).not_to eq(described_class.canonical_value([2, 1]))
    expect { described_class.canonical_mapping({ 1 => "value" }) }.to raise_error(ArgumentError)
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "inventory contracts" do
  around { |example| Dir.mktmpdir { |root| @root = root and example.run } }

  def capture(settings = {}, extras = [])
    described_class.new(config: Saboteur::Config.new(settings, root: @root), extra_files: extras)
  end

  def write(path, content = "1")
    absolute = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, content)
    absolute
  end

  it "pins input kinds and required flags and ignores ordinary non-Ruby files" do
    write("boot.rb")
    write("hook.rb")
    write("plugin.rb")
    write("extra.txt")
    write("lib/a.rb")
    write("lib/readme.txt")
    non_regular = File.realpath(write("pipe.rb"))
    allow(File).to receive(:file?).and_call_original
    allow(File).to receive(:file?).with(non_regular).and_return(false)
    instance = capture({ "require" => ["boot"], "hooks" => ["hook"], "sources" => ["plugin:Thing"] }, ["extra.txt"])
    entries = instance.snapshot.inventory.to_h { |entry| [entry.path, [entry.kind, entry.required, entry.state]] }
    expect(entries.fetch("boot.rb")).to eq(["boot", true, "present"])
    expect(entries.fetch("hook.rb")).to eq(["hook", true, "present"])
    expect(entries.fetch("plugin.rb")).to eq(["source_plugin", true, "present"])
    expect(entries.fetch("extra.txt")).to eq(["extra", true, "present"])
    expect(entries.fetch("lib/a.rb")).to eq(["ruby", true, "present"])
    expect(entries.fetch("Gemfile")).to eq(["manifest", false, "missing"])
    expect(entries.keys).not_to include("lib/readme.txt", "pipe.rb")
  end

  it "excludes configured report files and their directory contents" do
    write("out/report.rb")
    write("web/generated.rb")
    instance = capture({ "json_report" => "out/report.rb", "html_report" => "web" })
    snapshot = instance.snapshot
    expect(snapshot.inventory.map(&:path)).not_to include("out/report.rb", "web/generated.rb")
    expect(snapshot.issues).to eq(["output overlaps input: out/report.rb", "output overlaps input: web"])
  end

  it "refuses caches surrounding external required inputs and custom project inputs" do
    external = File.join(File.dirname(File.realpath(@root)), "external-#{File.basename(@root)}")
    FileUtils.mkdir_p(external)
    File.write(File.join(external, "boot.rb"), "1")
    begin
      snapshot = capture({ "cache_dir" => external, "require" => [File.join(external, "boot.rb")] }).snapshot
      expect(snapshot.issues).to include("cache directory overlaps inputs: external:#{File.realpath(external)}")
      write("custom/input.txt")
      snapshot = capture({ "cache_dir" => "custom" }, ["custom/input.txt"]).snapshot
      expect(snapshot.issues).to include("cache directory overlaps inputs: custom")
    ensure
      FileUtils.rm_rf(external)
    end
  end

  it "resolves existing extensionless inputs, suffixes and missing paths separately" do
    write("boot")
    write("suffix.rb")
    instance = capture({ "require" => %w[boot suffix missing missing.rb] })
    inventory = instance.snapshot.inventory
    expect(inventory.select { |entry| entry.kind == "boot" }.map(&:path)).to eq(%w[boot missing missing.rb suffix.rb])
    expect(inventory.find { |entry| entry.path == "boot" }.state).to eq("present")
    expect(inventory.find { |entry| entry.path == "suffix.rb" }.state).to eq("present")
    expect(instance.snapshot.issues).to eq(["missing required input: missing", "missing required input: missing.rb"])
  end

  it "reports exactly the changed file, config or runtime without false positives" do
    path = write("a.rb")
    instance = capture
    snapshot = instance.snapshot
    expect(instance.verify(snapshot).changes).to eq([])
    File.write(path, "2")
    expect(instance.verify(snapshot).changes.map(&:to_h)).to eq([{ path: "a.rb", reason: "changed" }])
    File.write(path, "1")
    configured = capture({ "baseline_timeout" => 7 })
    expect(configured.verify(snapshot).changes.map(&:to_h)).to eq([{ path: "settings", reason: "changed" }])
    runtime = described_class.new(config: Saboteur::Config.new({}, root: @root), runtime_identity: { other: 1 })
    expect(runtime.verify(snapshot).changes.map(&:to_h)).to eq([{ path: "runtime", reason: "changed" }])
    allow(Digest::SHA256).to receive(:file).with(File.realpath(path)).and_raise(IOError)
    expect(instance.verify(snapshot).changes.map(&:to_h)).to eq([{ path: "a.rb", reason: "unreadable" }])
  end

  it "requires current and previous completeness and format to verify" do
    instance = capture
    previous = instance.snapshot
    [previous.with(complete: false), previous.with(format_version: 2)].each do |invalid|
      result = instance.verify(invalid)
      expect(result.complete).to be(false)
      expect(result.unchanged).to be(false)
    end
    result = instance.verify(previous)
    expect(result.complete).to be(true)
    expect(result.current_digest).to eq(previous.digest)
    expect(result.issues).to eq([])
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "isolated validation boundaries" do
  it "checks schema before constructors and digest identity checks" do
    fields = { format_version: 1, complete: true, inventory: [], issues: [],
               digest: "a" * 64, settings_digest: "a" * 64, runtime_digest: "a" * 64 }
    expect { described_class.validate_snapshot_fields(fields.merge(extra: 1)) }
      .to raise_error(ArgumentError, /invalid snapshot fields/)
    %i[settings_digest runtime_digest].each do |key|
      expect { described_class.validate_snapshot_fields(fields.merge(key => "bad")) }
        .to raise_error(ArgumentError, /invalid fingerprint digest/)
    end
    entry = { path: "a.rb", kind: "ruby", required: true, state: "present", sha256: "a" * 64 }
    expect(described_class.valid_entry?(entry.merge(extra: 1))).to be(false)
    expect(described_class.valid_entry?(entry.merge(required: 1))).to be(false)
    expect(described_class.valid_path?("../a.rb")).to be(false)
    expect(described_class.valid_path?("/a.rb")).to be(false)
    expect(described_class.valid_state?("invalid", nil)).to be(false)
  end

  it "accepts complete required present and optional missing entries when restoring" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "a.rb"), "1")
      snapshot = described_class.new(config: Saboteur::Config.new({}, root: root)).snapshot
      expect(described_class.restore_snapshot(snapshot.to_h)).to eq(snapshot)
    end
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "filesystem edge contracts" do
  it "deduplicates and sorts overlap issues" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "z.rb"), "1")
      File.symlink(File.join(root, "z.rb"), File.join(root, "alias.rb"))
      config = Saboteur::Config.new({ "json_report" => "z.rb", "html_report" => "alias.rb", "cache_dir" => "." },
                                    root: root)
      instance = described_class.new(config: config)
      issues = instance.snapshot.issues
      expect(issues).to eq(issues.uniq.sort)
    end
  end

  it "exposes incomplete current state even with a complete previous snapshot" do
    Dir.mktmpdir do |root|
      instance = described_class.new(config: Saboteur::Config.new({}, root: root))
      previous = instance.snapshot
      File.symlink("/tmp", File.join(root, "link"))
      result = instance.verify(previous)
      expect(result.complete).to be(false)
      expect(result.unchanged).to be(false)
      expect(result.issues).to eq(["symlink input: link"])
    end
  end

  it "canonicalizes output aliases even when the leaf does not exist" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.symlink(File.join(root, "lib"), File.join(root, "alias"))
      config = Saboteur::Config.new({ "cache_dir" => "alias/missing" }, root: root)
      expect(described_class.new(config: config).snapshot.issues)
        .to include("cache directory overlaps inputs: lib/missing")
      File.write(File.join(root, "lib/a.rb"), "1")
      config = Saboteur::Config.new({ "json_report" => "alias/a.rb" }, root: root)
      instance = described_class.new(config: config)
      expect(instance.snapshot.inventory.map(&:path)).not_to include("lib/a.rb")
      expect(instance.snapshot.issues).to include("output overlaps input: lib/a.rb")
    end
  end

  it "prefers exact existing names over an available rb suffix" do
    Dir.mktmpdir do |root|
      %w[boot boot.rb already.rb already.rb.rb].each { |name| File.write(File.join(root, name), "1") }
      config = Saboteur::Config.new({ "require" => %w[boot already.rb] }, root: root)
      inventory = described_class.new(config: config).snapshot.inventory
      expect(inventory.select { |entry| entry.kind == "boot" }.map(&:path)).to eq(%w[already.rb boot])
    end
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "missing suffix boundary" do
  it "does not substitute a double suffix for an explicitly missing rb input" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "missing.rb.rb"), "1")
      config = Saboteur::Config.new({ "require" => ["missing.rb"] }, root: root)
      snapshot = described_class.new(config: config).snapshot
      expect(snapshot.issues).to eq(["missing required input: missing.rb"])
      expect(snapshot.inventory.find { |entry| entry.kind == "boot" }.path).to eq("missing.rb")
    end
  end
end

RSpec.describe Saboteur::Engine::RunFingerprint, "unreadable directories" do
  it "reports directory enumeration failure instead of claiming a complete inventory" do
    Dir.mktmpdir do |root|
      child = File.join(root, "blocked")
      FileUtils.mkdir_p(child)
      instance = described_class.new(config: Saboteur::Config.new({}, root: root))
      allow(Dir).to receive(:children).and_call_original
      allow(Dir).to receive(:children).with(File.realpath(child)).and_raise(Errno::EACCES)
      snapshot = instance.snapshot
      expect(snapshot.inventory.map(&:kind).uniq).to eq(["manifest"])
      expect(snapshot.complete).to be(false)
      expect(snapshot.issues).to eq(["unreadable directory: blocked"])
    end
  end
end
