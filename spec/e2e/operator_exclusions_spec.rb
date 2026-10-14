# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "operator enable and exclude controls (end to end)", :e2e do
  it "uses the formerly extended operators by default and permits CLI opt-out and re-enabling" do
    dir = copy_fixture("conditions")
    path = File.join(dir, "config", "saboteur.rb")
    File.write(path,
               File.read(path).sub('c.operators = ["condition_negation"]',
                                   'c.exclude_operators = ["condition_negation"]'))
    excluded = saboteur(dir)
    expect(mutants(excluded).map { |m| m["mutatorName"] }).not_to include("condition_negation")
    expect(excluded.json.dig("saboteur", "operatorPolicy", "excluded")).to eq(["condition_negation"])
    expect(excluded.out).to include("Excluded operators: condition_negation")
    enabled = saboteur(dir, "--operators", "condition_negation", "--exclude-operators", "")
    expect(mutants(enabled).map { |m| m["mutatorName"] }.uniq).to eq(["condition_negation"])
    disabled = saboteur(dir, "--operators", "condition_negation", "--exclude-operators", "condition_negation")
    expect(disabled.status).to eq(2)
    expect(disabled.err).to include("operator selection is empty")
    expect(disabled.json).to be_nil
    all = saboteur(dir, "--exclude-operators", "")
    expect(mutants(all).map { |m| m["mutatorName"] }).to include("condition_negation")
  end

  it "makes config and CLI exclusions agree in preview and refuses unknown exclusions before boot" do
    dir = copy_fixture("ranges")
    config = File.join(dir, "config", "saboteur.rb")
    File.write(config, File.read(config).sub('c.operators = ["range"]', 'c.exclude_operators = ["range"]'))
    normal = saboteur(dir)
    expect(mutants(normal).map { |m| m["mutatorName"] }).not_to include("range")
    config_preview = saboteur(dir, "--dry-run")
    cli_preview = saboteur(dir, "--dry-run", "--exclude-operators", "range")
    expect(config_preview.out).to eq(cli_preview.out)
    bad = saboteur(dir, "--exclude-operators", "not_real")
    expect(bad.status).to eq(2)
    expect(bad.err).to include("unknown operators: not_real")
  end
end
