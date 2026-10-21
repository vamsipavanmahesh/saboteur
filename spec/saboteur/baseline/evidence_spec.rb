# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "saboteur/baseline/evidence"

RSpec.describe Saboteur::Baseline::Evidence do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end
  let(:document) do
    file = File.join(@root, "probe.rb")
    File.write(file, "class Probe; def value; 1; end; end")
    subject = Saboteur::SubjectFinder.new.call(file).subjects.first
    mutation = Saboteur::MutationSource::Builtin.new.mutations_for(subject).first
    text = subject.apply(mutation.edits)
    capture = Saboteur::Baseline::RunEvidence.new(config: Saboteur::Config.new({}, root: @root))
    capture.plan([subject], [[[mutation, text]]])
    result = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :survived, mutated_source: text)
    JSON.parse(JSON.generate(capture.finish(results: [result], stable_suite: true, skipped_subjects: {},
                                            generation_events: [], omissions: [])))
  end

  it "adapts validated fresh producer evidence into a reasoned manifest without changing verdicts" do
    evidence = described_class.new(document)
    pending = evidence.manifest
    expect(pending["accepted"].first["reason"]).to eq("")
    manifest = Saboteur::Baseline::Manifest.new(evidence.manifest(reasons: "reviewed known gap"))
    expect(manifest.candidates.values).to eq(document["candidates"])
    expect(manifest.compatibility).to eq(document["compatibility"])
    expect(evidence.document).to be_frozen
  end

  it "refuses forged complete flags with omitted, undiscovered, invalid or unexecuted work" do
    %w[omissions discovery_failures inline_suppressions].each do |field|
      expect do
        described_class.new(document.merge(field => [{}]))
      end.to raise_error(Saboteur::ConfigError,
                         /omitted or undiscovered work/)
    end
    %w[invalid_syntax invalid_subject_syntax empty_generation unknown].each do |reason|
      event = { "file" => "probe.rb", "subject" => "Probe#value", "source" => "builtin",
                "operator" => nil, "reason" => reason }
      expect { described_class.new(document.merge("generation_events" => [event])) }
        .to raise_error(Saboteur::ConfigError, /generation/)
    end
    %w[skipped error resource_limit].each do |status|
      changed = document.merge("candidates" => [document["candidates"].first.merge("status" => status)])
      expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, /status/)
    end
  end

  it "binds snapshot settings and runtime to exact producer compatibility" do
    %w[config runtime scope generator].each do |field|
      compatibility = document["compatibility"].merge(field => {})
      expect { described_class.new(document.merge("compatibility" => compatibility)) }
        .to raise_error(Saboteur::ConfigError)
    end
    changed = Marshal.load(Marshal.dump(document))
    changed["compatibility"]["config"]["seed"] += 1
    expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, /settings/)
    changed = Marshal.load(Marshal.dump(document))
    changed["compatibility"]["runtime"]["patchlevel"] += 1
    expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, /settings/)
  end

  it "rejects missing, stale-version and mismatched operator policies" do
    changed = Marshal.load(Marshal.dump(document))
    changed["compatibility"]["config"].delete("operator_policy")
    expect { described_class.new(rebuilt(changed)) }
      .to raise_error(Saboteur::ConfigError,
                      "baseline operator policy is incompatible; re-propose with baseline propose")

    changed = Marshal.load(Marshal.dump(document))
    changed["compatibility"]["config"]["operator_policy"]["version"] = 1
    expect { described_class.new(rebuilt(changed)) }
      .to raise_error(Saboteur::ConfigError, /operator policy is incompatible/)

    changed = Marshal.load(Marshal.dump(document))
    changed["compatibility"]["config"]["operators"] = ["range"]
    expect { described_class.new(rebuilt(changed)) }
      .to raise_error(Saboteur::ConfigError, /operator policy mismatch/)
  end

  def identity_digest(value)
    Digest::SHA256.hexdigest(JSON.generate(Saboteur::Engine::RunFingerprint.canonical_value(value)))
  end

  def rebuilt(changed)
    config = changed["compatibility"]["config"]
    runtime = changed["compatibility"]["runtime"]
    settings = Saboteur::Config.new(config.except("operator_policy"), root: @root)
    snapshot = Saboteur::Engine::RunFingerprint.new(config: settings,
                                                    runtime_identity: runtime).snapshot
    changed["snapshot"] = JSON.parse(JSON.generate(snapshot.to_h))
    changed
  end

  it "checks fresh config, scope and generator bindings even after snapshot hashes are recomputed" do
    [{ "since" => "main" }, { "incremental" => true }].each do |settings|
      changed = Marshal.load(Marshal.dump(document))
      changed["compatibility"]["config"].merge!(settings)
      expect { described_class.new(rebuilt(changed)) }.to raise_error(Saboteur::ConfigError, /nonfresh/)
    end
    changed = Marshal.load(Marshal.dump(document))
    changed["compatibility"]["scope"]["subjects"] = ["Other"]
    expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, /scope/)
    %w[saboteur sources plugins].each do |field|
      changed = Marshal.load(Marshal.dump(document))
      changed["compatibility"]["generator"][field] = "wrong"
      expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, /generator/)
    end
  end

  it "retains allowed generation events, rejecting malformed history and inconsistent claims" do
    event = { "file" => "probe.rb", "subject" => "Probe#value", "source" => "builtin",
              "operator" => "body", "reason" => "duplicate" }
    changed = document.merge("generation_events" => [event])
    expect(described_class.new(changed).document["generation_events"]).to eq([event])
    [nil, {}, [event.merge("extra" => true)], [event.except("source")]].each do |events|
      expect { described_class.new(document.merge("generation_events" => events)) }
        .to raise_error(Saboteur::ConfigError, /fields|events/)
    end
    expect { described_class.new(document.merge("issues" => ["hidden"])) }
      .to raise_error(Saboteur::ConfigError, /incomplete/)
    expect { described_class.new(document.merge("planned" => nil)) }
      .to raise_error(Saboteur::ConfigError, /plan/)
    expect { described_class.new(document.merge("planned" => [document["planned"].first.merge("extra" => true)])) }
      .to raise_error(Saboteur::ConfigError, /baseline evidence fields/)
    expect { described_class.new(document.merge("candidates" => nil)) }
      .to raise_error(Saboteur::ConfigError, /candidates/)
  end

  it "never accepts a detected mutant and requires a complete restorable fingerprint" do
    changed = document.merge("candidates" => [document["candidates"].first.merge("status" => "killed")])
    expect(described_class.new(changed).manifest["accepted"]).to eq([])
    snapshot = document["snapshot"].merge("complete" => false, "issues" => ["missing input"])
    expect { described_class.new(document.merge("snapshot" => snapshot)) }
      .to raise_error(Saboteur::ConfigError, /fingerprint/)
    expect { described_class.new(document.merge("compatibility" => document["compatibility"].merge("extra" => true))) }
      .to raise_error(Saboteur::ConfigError, /baseline evidence fields/)
  end

  it "rejects extra compatibility keys even when their snapshot hashes are internally consistent" do
    %w[config runtime].each do |field|
      changed = Marshal.load(Marshal.dump(document))
      changed["compatibility"][field]["unknown"] = true
      if field == "runtime"
        changed = rebuilt(changed)
      else
        snapshot = changed["snapshot"]
        snapshot["settings_digest"] = identity_digest(changed["compatibility"]["config"])
        inputs = { format: 1, files: snapshot["inventory"], settings: snapshot["settings_digest"],
                   runtime: snapshot["runtime_digest"] }
        snapshot["digest"] = identity_digest(inputs)
      end
      expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, /baseline evidence fields/)
    end
    changed = document.merge("compatibility" => document["compatibility"].merge("other" => true))
    expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, /baseline evidence fields/)
    expect { described_class.new(document.merge("planned" => [])) }
      .to raise_error(Saboteur::ConfigError, /empty candidate plan/)
  end

  it "binds nonempty custom plugin inventory exactly while excluding ordinary source files" do
    original = document
    plugin = File.join(@root, "plugin.rb")
    File.write(plugin, "class Plugin; end")
    changed = Marshal.load(Marshal.dump(original))
    changed["compatibility"]["config"]["sources"] = ["plugin.rb:Plugin"]
    changed["compatibility"]["generator"]["sources"] = ["plugin.rb:Plugin"]
    changed = rebuilt(changed)
    changed["compatibility"]["generator"]["plugins"] = changed["snapshot"]["inventory"].select do |entry|
      entry["kind"] == "source_plugin"
    end
    expect(changed["compatibility"]["generator"]["plugins"].size).to eq(1)
    expect(described_class.new(changed).manifest(reasons: "reviewed")["metadata"]["generator"])
      .to eq(changed["compatibility"]["generator"])
    changed["compatibility"]["generator"]["plugins"] = []
    expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, /generator/)
  end

  it "refuses extra generator fields with an explicit evidence boundary error" do
    changed = Marshal.load(Marshal.dump(document))
    changed["compatibility"]["generator"]["extra"] = true
    expect { described_class.new(changed) }.to raise_error(Saboteur::ConfigError, /baseline evidence fields/)
  end

  it "rejects missing extra or inconsistent plans and corrupted snapshots" do
    [[], document["planned"] * 2, [document["planned"].first.merge("context" => "b" * 64)]].each do |plan|
      expect { described_class.new(document.merge("planned" => plan)) }
        .to raise_error(Saboteur::ConfigError, /plan/)
    end
    snapshot = document["snapshot"].merge("digest" => "a" * 64)
    expect { described_class.new(document.merge("snapshot" => snapshot)) }.to raise_error(Saboteur::ConfigError)
    expect { described_class.new(document.merge("proposable" => false)) }
      .to raise_error(Saboteur::ConfigError, /incomplete/)
    expect { described_class.new(document.merge("extra" => true)) }
      .to raise_error(Saboteur::ConfigError, /baseline evidence fields/)
  end
end
