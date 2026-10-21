# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::AgentProvenance do
  it "is mixed into Saboteur::CLI like the other extracted pieces (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the agent provenance builder and settings, moved out of CLI itself" do
    expect(described_class.private_instance_methods(false)).to include(
      :agent_provenance, :agent_settings, :typed_settings, :agent_mode
    )
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(
      :agent_provenance, :agent_settings, :typed_settings, :agent_mode
    )
  end
end

# Executing pins: the provenance builder and its settings helpers, driven
# through a real run with a stubbed engine (#334). Structural checks alone
# never execute the extracted code, so the dogfood survivors above hide here.
RSpec.describe "Saboteur::CLI::AgentProvenance execution (#334)" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    Saboteur::CLI.new(argv, out:, err:)
  end

  def run_with(config_body, *argv)
    Dir.mktmpdir do |root|
      path = File.join(root, "saboteur.rb")
      File.write(path, config_body)
      command = cli("run", "--agent", "--config", path, *argv)
      allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
      command.call
      command.config
      return command
    end
  end

  empty_config = "Saboteur.configure { |c| }"

  it "records --all only when a whole-suite run resolved no named tests" do
    all_set = run_with(empty_config, "--all").send(:agent_settings)
    expect(all_set[:all]).to be(true)

    with_tests = run_with('Saboteur.configure { |c| c.tests = ["x_spec.rb"] }', "--all").send(:agent_settings)
    expect(with_tests).not_to have_key(:all)

    by_selection = run_with('Saboteur.configure { |c| c.test_selection = "all" }').send(:agent_settings)
    expect(by_selection[:all]).to be(true)

    plain = run_with(empty_config).send(:agent_settings)
    expect(plain).not_to have_key(:all)
  end

  it "keeps the CLI-only availability switches in the settings only when given" do
    flagged = run_with(empty_config, "--allow-hazardous", "--allow-focus").send(:agent_settings)
    expect(flagged[:allow_hazardous]).to be(true)
    expect(flagged[:allow_focus]).to be(true)

    plain = run_with(empty_config).send(:agent_settings)
    expect(plain).not_to have_key(:allow_hazardous)
    expect(plain).not_to have_key(:allow_focus)
    expect(plain).not_to have_key(:max_duration_ok)
  end

  it "keeps an explicit --no-max-duration-ok and drops a nil one" do
    off = run_with("Saboteur.configure { |c| c.max_duration_ok = true }", "--no-max-duration-ok")
    expect(off.send(:agent_settings)[:max_duration_ok]).to be(false)
    expect(run_with(empty_config).send(:agent_settings)).not_to have_key(:max_duration_ok)
  end

  it "slices only the known setting flags and merges the configured operator lists" do
    config = "Saboteur.configure { |c| c.operators = %w[comparison]; c.exclude_operators = %w[range] }"
    settings = run_with(config, "--jobs", "2", "--verbose", "--test", "a_spec.rb").send(:agent_settings)
    expect(settings[:jobs]).to eq(2)
    expect(settings[:operators]).to eq(%w[comparison])
    expect(settings[:exclude_operators]).to eq(%w[range])
    expect(settings).not_to have_key(:verbose)
    expect(settings).not_to have_key(:tests)
  end

  it "fills every provenance field from the run, guessed tests winning over config tests" do
    command = run_with("Saboteur.configure { |c| c.tests = %w[from_config.rb] }")
    report = double(seed: 7, referenced: {})
    tree = instance_double("tree", head: "abc", label: "dirty", changed_files: %w[a.rb])
    engine = instance_double(Saboteur::Engine, guessed_tests: %w[from_engine.rb])
    prov = command.send(:agent_provenance, report, tree, engine)
    expect(prov.tests).to eq(%w[from_engine.rb])
    expect(prov.incremental).to eq(command.config["incremental"])
    expect(prov.settings).to eq(command.send(:agent_settings))
    expect(prov.typed_settings).to eq(command.send(:typed_settings))
    expect(prov.sources).to eq([])
    expect(prov.mode).to eq("full")
  end

  it "falls back to the configured tests when no tests were guessed" do
    command = run_with("Saboteur.configure { |c| c.tests = %w[from_config.rb] }")
    report = double(seed: 7, referenced: {})
    tree = instance_double("tree", head: "abc", label: "dirty", changed_files: %w[a.rb])
    engine = instance_double(Saboteur::Engine, guessed_tests: nil)
    expect(command.send(:agent_provenance, report, tree, engine).tests).to eq(%w[from_config.rb])
  end

  it "carries the files chosen by reference from the report" do
    command = run_with(empty_config)
    report = double(seed: 7, referenced: { "lib/a.rb" => ["spec/x_spec.rb"] })
    tree = double(head: "abc", label: "dirty", changed_files: [])
    engine = instance_double(Saboteur::Engine, guessed_tests: nil)

    expect(command.send(:agent_provenance, report, tree, engine).referenced).to eq("lib/a.rb" => ["spec/x_spec.rb"])
  end

  it "labels the mode from positional sources" do
    with_source = run_with(empty_config, "lib/foo.rb")
    expect(with_source.send(:agent_mode)).to eq("files")
    expect(run_with(empty_config).send(:agent_mode)).to eq("full")
  end

  it "labels replay ahead of diff when --id and --since combine" do
    both = run_with('Saboteur.configure { |c| c.since = "origin/main" }', "--id", "abc123", "lib/foo.rb")
    expect(both.send(:agent_mode)).to eq("replay")
  end

  it "labels replay and diff modes ahead of files or full" do
    replay = run_with(empty_config, "--id", "abc123", "lib/foo.rb")
    expect(replay.send(:agent_mode)).to eq("replay")
    diff = run_with('Saboteur.configure { |c| c.since = "origin/main" }')
    expect(diff.send(:agent_mode)).to eq("diff")
  end

  it "carries the positional sources into the provenance record" do
    command = run_with(empty_config, "lib/foo.rb")
    report = double(seed: 7, referenced: {})
    tree = double(head: "abc", label: "dirty", changed_files: %w[a.rb])
    engine = instance_double(Saboteur::Engine, guessed_tests: nil)
    prov = command.send(:agent_provenance, report, tree, engine)
    expect(prov.sources).to eq(["lib/foo.rb"])
    expect(prov.mode).to eq("files")
  end

  it "hands the typed settings to the provenance it builds" do
    command = run_with(empty_config, "--jobs", "2")
    given = nil
    allow(Saboteur::Reporter::Agent::Provenance).to receive(:new) { |**kw| given = kw }
    report = double(seed: 7, referenced: {})
    tree = double(head: "abc", label: "clean", changed_files: [])
    engine = instance_double(Saboteur::Engine, guessed_tests: nil)
    command.send(:agent_provenance, report, tree, engine)
    expect(given).to include(typed_settings: [:jobs], seed: 7)
  end
end
