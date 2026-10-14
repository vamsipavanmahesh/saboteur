# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "operator selection and source-only preview" do
  let(:target) { subjects_in("class PreviewTarget\n  def m(x)\n    x + 1\n  end\nend\n").first }

  it "keeps every existing operator by default and resolves tiers" do
    registry = Saboteur::MutationSource::OperatorRegistry
    expect(registry.resolve([])).to eq(registry.resolve(["all"]))
    expect(registry.resolve(["all"])).to eq(registry::DESCRIPTIONS.keys)
    expect(registry::TIERS.keys).to eq(["all"])
  end

  it "keeps all operators default-on and validates its names in inline suppression" do
    registry = Saboteur::MutationSource::OperatorRegistry
    %w[range operator_assignment condition_negation].each do |name|
      expect(registry.resolve([])).to include(name)
      expect(registry.resolve([name])).to eq([name])
      source = "class OptIn\n  def m(x)\n    x + 1 # saboteur:disable-line #{name} reason=checked\n  end\nend\n"
      subject = subjects_in(source).first
      expect { Saboteur::InlineSuppression.new(subject.file, subject.file_source) }.not_to raise_error
    end
  end

  it "subtracts exclusions after selection, rejects unknowns and permits excluding all" do
    registry = Saboteur::MutationSource::OperatorRegistry
    expect(registry.select([], [])).to eq(registry::DESCRIPTIONS.keys)
    expect(registry.select(%w[arithmetic range], %w[range])).to eq(["arithmetic"])
    expect { Saboteur::Config.new({ "exclude_operators" => ["all"] }) }
      .to raise_error(Saboteur::ConfigError, /operator selection is empty/)
    expect { registry.select([], ["typo"]) }.to raise_error(Saboteur::ConfigError, /unknown operators: typo/)
    expect { registry.resolve(["extended"]) }.to raise_error(Saboteur::ConfigError, /were removed.*concrete names/)
    expect { registry.resolve(["core"]) }.to raise_error(Saboteur::ConfigError, /old core set exclude range/)
    expect(Saboteur::MutationSource::Builtin.new(exclude_operators: ["arithmetic"])
      .mutations_for(target).map(&:operator)).not_to include("arithmetic")
  end

  it "loads exclusions from config, with CLI lists replacing config lists" do
    root = File.dirname(target.file)
    path = File.join(root, "operators.rb")
    File.write(path, 'Saboteur.configure { |c| c.exclude_operators = ["arithmetic", "range"] }')
    settings = Saboteur::Config.load(root: root, path: path)
    expect(settings["exclude_operators"]).to eq(%w[arithmetic range])
    expect(Saboteur::Engine::Candidates.build_sources(settings).first.mutations_for(target).map(&:operator))
      .not_to include("arithmetic")
    command = Saboteur::CLI.new(["run", "--config", path, "--exclude-operators", "range,condition_negation"])
    command.parser.parse!(["--config", path, "--exclude-operators", "range,condition_negation"])
    expect(command.options[:exclude_operators]).to eq(%w[range condition_negation])
    expect(command.config["exclude_operators"]).to eq(%w[range condition_negation])
    expect { Saboteur::Config.new({ "exclude_operators" => ["typo"] }) }.to raise_error(Saboteur::ConfigError)
    first = Saboteur::Engine::RunFingerprint.new(config: settings).snapshot
    other = Saboteur::Config.new(settings.to_h.merge("exclude_operators" => []), root: root)
    other_snapshot = Saboteur::Engine::RunFingerprint.new(config: other).snapshot
    expect(first.settings_digest).not_to eq(other_snapshot.settings_digest)
    expect(Saboteur::Engine::VERDICT_INPUTS).to include("exclude_operators")
  end

  it "shows current config on/off with examples, and repeated CLI lists use the last value" do
    root = File.dirname(target.file)
    path = File.join(root, "selection.rb")
    File.write(path, 'Saboteur.configure { |c| c.exclude_operators = ["range"] }')
    out = StringIO.new
    command = Saboteur::CLI.new(["run", "--config", path, "--list-operators"], out: out, err: StringIO.new)
    expect(command.call).to eq(0)
    expect(out.string).to include("range  off", "1..3 -> 1...3", "arithmetic  on")
    parsed = Saboteur::CLI.new([])
    parsed.parser.parse!(%w[--operators range --operators arithmetic --exclude-operators range --exclude-operators
                            arithmetic])
    expect(parsed.options).to include(operators: ["arithmetic"], exclude_operators: ["arithmetic"])
    expect { parsed.config }.to raise_error(Saboteur::ConfigError, /operator selection is empty/)
    expect { Saboteur::Config.new({ "exclude_operators" => ["arithmeti"] }) }
      .to raise_error(Saboteur::ConfigError, /arithmeti.*Did you mean arithmetic.*--list-operators/)
  end

  it "keeps excluded concrete names valid but dormant in inline suppression" do
    source = "class Dormant\n  def m(x)\n    x * 2 " \
             "# saboteur:disable-line condition_negation reason=checked\n  end\nend\n"
    subject = subjects_in(source).first
    settings = Saboteur::Config.new({ "exclude_operators" => ["condition_negation"] })
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    Saboteur::Engine::Candidates.new(Saboteur::Engine::Candidates.build_sources(settings), diagnostics).for(subject)
    expect(diagnostics.inline_suppressions).to eq([])
    before = Saboteur::MutationSource::Builtin.new(operators: ["arithmetic"]).mutations_for(target)
    after = Saboteur::MutationSource::Builtin.new.mutations_for(target).select { |m| m.operator == "arithmetic" }
    digests = lambda { |list|
      list.map do |m|
        m.digest(subject_start: target.start_byte, original_source: target.file_source)
      end
    }
    expect(digests.call(before)).to eq(digests.call(after))
  end

  it "records every exact policy field and matches registry examples" do
    registry = Saboteur::MutationSource::OperatorRegistry
    expect(registry.policy(%w[range arithmetic], ["range"]))
      .to eq("version" => 2, "selected" => %w[range arithmetic], "excluded" => ["range"],
             "effective" => ["arithmetic"])
    expect(Saboteur::MutationSource::OperatorExamples::EXAMPLES.keys.sort).to eq(registry::DESCRIPTIONS.keys.sort)
    out = StringIO.new
    registry.list(out, names: ["range"], excluded: [])
    expect(out.string.lines.find { |line| line.start_with?("range  ") })
      .to eq("range  on  Swap inclusive and exclusive bounded ranges  1..3 -> 1...3\n")
    expect(registry.suggestion("not_real_operator")).to eq("")
    expect(registry.suggestion("arithmeti")).to eq("Did you mean arithmetic?")
    expect { registry.resolve(%w[arithmetic range wrong]) }
      .to raise_error(Saboteur::ConfigError, /unknown operators: wrong.*--list-operators/)
    expect { registry.resolve(%w[core extended]) }
      .to raise_error(Saboteur::ConfigError, /operator tiers core, extended were removed/)
  end

  it "uses the closest first spelling suggestion and only checks legacy names when present" do
    checker = instance_double(DidYouMean::SpellChecker, correct: %w[arithmetic range])
    allow(DidYouMean::SpellChecker).to receive(:new).and_return(checker)
    expect(Saboteur::MutationSource::OperatorRegistry.suggestion("typo")).to eq("Did you mean arithmetic?")
    expect { Saboteur::MutationSource::OperatorRegistry.resolve(%w[range arithmetic]) }.not_to raise_error
    expect { Saboteur::MutationSource::OperatorRegistry.resolve(%w[arithmeti nope]) }
      .to raise_error(Saboteur::ConfigError, /unknown operators: arithmeti, nope.*Did you mean arithmetic/)
  end

  it "reports both legacy names and every available choice exactly" do
    registry = Saboteur::MutationSource::OperatorRegistry
    expect { registry.resolve(%w[core extended]) }
      .to raise_error(Saboteur::ConfigError,
                      "operator tiers core, extended were removed: use concrete names or all; " \
                      "for the old core set exclude range,operator_assignment,condition_negation")
    checker = instance_double(DidYouMean::SpellChecker, correct: %w[arithmetic range])
    expect(DidYouMean::SpellChecker).to receive(:new).with(dictionary: registry::DESCRIPTIONS.keys).and_return(checker)
    choices = (registry::DESCRIPTIONS.keys + ["all"]).join(", ")
    expected = "unknown operators: arithmeti, typo. Valid names: #{choices}. " \
               "Did you mean arithmetic? See --list-operators."
    expect { registry.resolve(%w[arithmeti typo]) }.to raise_error(Saboteur::ConfigError, expected)
  end

  it "restricts builtin generation and rejects unknown names" do
    source = Saboteur::MutationSource::Builtin.new(operators: ["arithmetic"])
    expect(source.mutations_for(target).map(&:operator)).to eq(["arithmetic"])
    expect { Saboteur::Config.new({ "operators" => ["typo"] }) }
      .to raise_error(Saboteur::ConfigError, /unknown operators: typo.*Valid names:.*all/)
  end

  it "lists operators without booting the engine" do
    out = StringIO.new
    expect(Saboteur::Engine).not_to receive(:new)
    expect(Saboteur::CLI.new(%w[run --list-operators], out: out).call).to eq(0)
    expect(out.string).to include("argument_removal  on", "endpoint_replacement  on", "chain_removal  on",
                                  "range  on", "operator_assignment  on", "condition_negation  on")
  end

  describe "chain_removal" do
    let(:chain) { subjects_in("class ChainTarget\n  def m(a)\n    a.b.c\n  end\nend\n").first }

    it "is a registered core operator, so default and tier selections keep its mutants" do
      registry = Saboteur::MutationSource::OperatorRegistry
      expect(registry::DESCRIPTIONS).to include("chain_removal")
      expect(registry.resolve([])).to include("chain_removal")
      expect(registry.resolve(["all"])).to include("chain_removal")
      expect(registry.resolve(["all"])).to include("chain_removal")
      operators = Saboteur::MutationSource::Builtin.new.mutations_for(chain).map(&:operator)
      expect(operators).to include("chain_removal")
    end

    it "can be named alone, and a different selection leaves it out" do
      named = Saboteur::MutationSource::Builtin.new(operators: ["chain_removal"])
      expect(named.mutations_for(chain).map(&:operator).uniq).to eq(["chain_removal"])
      other = Saboteur::MutationSource::Builtin.new(operators: ["arithmetic"])
      expect(other.mutations_for(chain).map(&:operator)).not_to include("chain_removal")
      expect(Saboteur::Config.new({ "operators" => ["chain_removal"] })["operators"]).to eq(["chain_removal"])
    end

    it "is a valid name in an inline suppression, and an unknown name still is not" do
      accepted = "class Chain\n  def m(a)\n    a.b.c # saboteur:disable-line chain_removal reason=checked\n  end\nend\n"
      subject = subjects_in(accepted).first
      expect { Saboteur::InlineSuppression.new(subject.file, subject.file_source) }.not_to raise_error
      rejected = accepted.sub("chain_removal", "chain_removl")
      other = subjects_in(rejected).first
      expect { Saboteur::InlineSuppression.new(other.file, other.file_source) }.to raise_error(Saboteur::ConfigError)
    end

    it "shows up in a default source-only preview" do
      out = StringIO.new
      Dir.chdir(File.dirname(chain.file)) do
        cli = Saboteur::CLI.new(["run", File.basename(chain.file), "--dry-run"], out: out)
        expect(cli.call).to eq(0)
      end
      expect(out.string).to match(/ChainTarget#m\s+\d+ mutants/)
      out.truncate(0)
      Dir.chdir(File.dirname(chain.file)) do
        Saboteur::CLI.new(["run", File.basename(chain.file), "--dry-run", "--operators", "chain_removal"],
                          out: out).call
      end
      expect(out.string).to include("ChainTarget#m  1 mutants")
    end
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
    expect(out.string).to include("Choose operator names (default: all)", "List operator names and descriptions",
                                  "Preview mutants without boot, tests, forks or report writes")
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
      .to raise_error(Saboteur::ConfigError) { |error| expect(error.message).to include("bad, other", "all") }
  end
end
