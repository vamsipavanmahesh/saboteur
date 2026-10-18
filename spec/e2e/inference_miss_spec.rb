# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "inference miss", :e2e do
  # A dry-inflector-shaped layout keeps specs under spec/unit/, off the
  # conventional spec/dry/inflector/ path (#658). Inference mirrors
  # directories, flattens below the namespace, and falls back to a unique
  # parent-directory-plus-basename suffix, so a plain spec/unit/ layout is
  # covered; the fail-closed stop survives when the suffix anchor matches
  # two specs and guessing either one could run the wrong suite.
  it "stops before boot with exit 2, naming the expected spec, the candidates and the recovery" do
    dir = copy_fixture("inference_miss")
    run = saboteur(dir)

    expect(run.status).to eq(2), run.out + run.err
    expect(run.out).to eq("")
    expect(run.err).to include(
      "no spec found for lib/dry/inflector/acronyms.rb (expected spec/dry/inflector/acronyms_spec.rb",
      "; found: ",
      "spec/unit/inflector/acronyms_spec.rb",
      "spec/integration/inflector/acronyms_spec.rb",
      "so nothing ran.",
      "Re-run the same command with one --test per existing spec path, or append --all " \
      "to use the whole suite without changing the source scope."
    )
  end

  it "runs when the documented recovery names the suite" do
    dir = copy_fixture("inference_miss")
    run = saboteur(dir, "--all")

    expect(run.status).to eq(0), other_outcomes(run)
  end

  it "runs when the documented recovery names the specs" do
    dir = copy_fixture("inference_miss")
    run = saboteur(dir, "--test", "spec/unit/inflector/acronyms_spec.rb")

    expect(run.status).to eq(0), other_outcomes(run)
  end
end
