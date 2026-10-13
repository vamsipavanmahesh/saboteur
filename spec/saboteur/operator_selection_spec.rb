# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "operator selection and source-only preview" do
  let(:target) { subjects_in("class PreviewTarget\n  def m(x)\n    x + 1\n  end\nend\n").first }

  it "keeps every existing operator by default and resolves tiers" do
    registry = Saboteur::MutationSource::OperatorRegistry
    expect(registry.resolve([])).to eq(registry.resolve(["core"]))
    expect(registry.resolve(["all"])).to eq(registry::DESCRIPTIONS.keys)
    expect(registry.resolve(["extended"])).to eq([])
  end

  it "restricts builtin generation and rejects unknown names" do
    source = Saboteur::MutationSource::Builtin.new(operators: ["arithmetic"])
    expect(source.mutations_for(target).map(&:operator)).to eq(["arithmetic"])
    expect { Saboteur::Config.new({ "operators" => ["typo"] }) }
      .to raise_error(Saboteur::ConfigError, /unknown operators: typo.*Valid names:.*core, extended, all/)
  end

  it "lists operators without booting the engine" do
    out = StringIO.new
    expect(Saboteur::Engine).not_to receive(:new)
    expect(Saboteur::CLI.new(%w[run --list-operators], out: out).call).to eq(0)
    expect(out.string).to include("argument_removal  core", "endpoint_replacement  core")
  end

  it "previews explicit sources without loading tests, forking or writing reports" do
    out = StringIO.new
    expect(Process).not_to receive(:fork)
    expect(Saboteur::Engine::Boot).not_to receive(:new)
    expect(Saboteur::Engine::CoverageStore).not_to receive(:new)
    Dir.chdir(File.dirname(target.file)) do
      cli = Saboteur::CLI.new(["run", File.basename(target.file), "--dry-run", "--operators", "arithmetic"], out: out)
      expect(cli.call).to eq(0)
    end
    expect(out.string).to include("PreviewTarget#m  1 mutants", "Total: 1 mutants", "no estimate")
  end

  it "includes operator selection in the run fingerprint" do
    first = Saboteur::Config.new({ "operators" => ["arithmetic"] })
    second = Saboteur::Config.new({ "operators" => ["comparison"] })
    expect(Saboteur::Engine::RunFingerprint.new(config: first).snapshot.settings_digest)
      .not_to eq(Saboteur::Engine::RunFingerprint.new(config: second).snapshot.settings_digest)
  end
  it "counts cap drops and reads a matching cache for a duration estimate without changing it" do
    root = File.dirname(target.file)
    config = Saboteur::Config.new({ "include" => ["*.rb"], "max_mutants_per_method" => 1 }, root: root)
    map = Saboteur::Selection::CoverageMap.new(lines: { target.file => { 3 => ["t1"] } }, tests: ["t1"],
                                               durations: { "t1" => 0.25 })
    cache = File.join(root, ".saboteur", "coverage.json")
    map.save(cache)
    receipt = File.join(root, ".saboteur", "preview.json")
    identity = Saboteur::Engine::RunFingerprint.new(config: config).snapshot.digest
    File.write(receipt, JSON.generate(path: cache, fingerprint: identity))
    before = File.read(cache)
    out = StringIO.new
    Saboteur::Preview.new(config, out: out, err: StringIO.new).call
    expect(out.string).to include("Total: 1 mutants", "dropped by max_mutants_per_method",
                                  "Estimated baseline covering-test work: 0.25 s")
    expect(File.read(cache)).to eq(before)
  end
  it "exposes complete help and parses the named list as separate values" do
    out = StringIO.new
    command = Saboteur::CLI.new(%w[run --help], out: out)
    expect(command.call).to eq(0)
    expect(out.string).to include("Choose operator names or tiers", "List operator names, descriptions and tiers",
                                  "Preview mutants without boot, tests, forks or report writes",
                                  "Stryker JSON report path", "Self-contained HTML report path",
                                  "text (default) or agent: one bounded JSON summary on stdout,")
    parsed = Saboteur::CLI.new(%w[run --operators arithmetic,comparison])
    parsed.parser.parse!(%w[--operators arithmetic,comparison])
    expect(parsed.options[:operators]).to eq(%w[arithmetic comparison])
  end

  it "passes the config selection to builtin sources" do
    config = Saboteur::Config.new({ "operators" => ["arithmetic"] })
    source = Saboteur::Engine::Candidates.build_sources(config).first
    expect(source.mutations_for(target).map(&:operator)).to eq(["arithmetic"])
  end
  it "honors configured arid patterns when building sources" do
    config = Saboteur::Config.new({ "arid" => ["x"] })
    source = Saboteur::Engine::Candidates.build_sources(config).first
    expect(source.mutations_for(target).map(&:operator)).not_to include("arithmetic")
  end

  it "does not send preview switches into Config overrides" do
    parsed = Saboteur::CLI.new(%w[run --dry-run])
    parsed.parser.parse!(%w[--dry-run])
    expect(parsed.send(:overrides)).not_to have_key(:dry_run)
    parsed.options[:config] = "config/saboteur.rb"
    parsed.options[:id] = "a"
    parsed.options[:list_operators] = true
    expect(parsed.send(:overrides)).not_to have_key(:config)
    expect(parsed.send(:overrides)).not_to have_key(:id)
    expect(parsed.send(:overrides)).not_to have_key(:list_operators)
    expect(parsed.config).to be_a(Saboteur::Config)
  end
  it "names every unknown selection alongside every valid name" do
    expect { Saboteur::MutationSource::OperatorRegistry.resolve(%w[bad other]) }
      .to raise_error(Saboteur::ConfigError) { |error| expect(error.message).to include("bad, other", "core, extended, all") }
  end
end
