# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "shellwords"

# The printed rerun and replay commands leave out empty operator lists the
# config supplies, keep a typed empty list that clears a config value, and
# reproduce the same mutant selection when run (#317).
RSpec.describe "operator flags in generated commands (end to end)", :e2e do
  let(:dir) { copy_fixture("conditions") }
  let(:config) { File.join(dir, "config", "saboteur.rb") }

  def rerun_words(run)
    Shellwords.split(JSON.parse(run.out).dig("next", "rerun"))
  end

  # The command minus "saboteur run", without --agent so the JSON report is
  # written for comparison.
  def run_printed(words)
    saboteur(dir, *(words.drop(2) - ["--agent"]))
  end

  def operator_names(run)
    mutants(run).map { |m| m["mutatorName"] }.uniq.sort
  end

  it "leaves out operator lists that are empty in the config" do
    File.write(config, File.read(config).sub(/^\s*c\.operators = .*\n/, ""))
    words = rerun_words(saboteur(dir, "--agent"))
    expect(words).not_to include("--operators", "--exclude-operators")
    expect(Shellwords.join(words)).not_to include("''")
  end

  it "keeps a typed empty list that clears a config exclusion, and the command reproduces the selection" do
    File.write(config, File.read(config).sub('c.operators = ["condition_negation"]',
                                             'c.exclude_operators = ["condition_negation"]'))
    original = saboteur(dir, "--exclude-operators", "")
    expect(operator_names(original)).to include("condition_negation")
    words = rerun_words(saboteur(dir, "--agent", "--exclude-operators", ""))
    expect(words.each_cons(2).to_a).to include(["--exclude-operators", ""])
    expect(words).not_to include("--operators")
    expect(operator_names(run_printed(words))).to eq(operator_names(original))
  end

  it "keeps a non-empty config list, quoted, and the command reproduces the selection" do
    original = saboteur(dir)
    words = rerun_words(saboteur(dir, "--agent"))
    expect(words.each_cons(2).to_a).to include(["--operators", "condition_negation"])
    expect(words).not_to include("--exclude-operators")
    expect(operator_names(run_printed(words))).to eq(operator_names(original))
    expect(operator_names(original)).to eq(["condition_negation"])
  end
end
