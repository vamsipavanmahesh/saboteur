# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# #1316 (P5): the --quiet contract is findings, score and verdict, so a
# --subject run under --quiet hides the two-line spec-inference notice.
# Real warnings - here the unconfirmed-survivors line - still print.
RSpec.describe "--quiet hides the spec-inference notice", :e2e do
  let(:dir) { copy_fixture("wrapped") }

  let(:unconfirmed_line) do
    "saboteur: survivors unconfirmed: no whole-suite coverage map; run `saboteur run --all` to build one"
  end

  it "prints only the real warning on stderr, with the findings on stdout" do
    run = saboteur(dir, "--quiet", "--subject", "Ledger#record")

    expect(run.err).to eq("\n#{unconfirmed_line}\n")
    expect(run.out).to include("lib/ledger.rb:13 Ledger#record")
    expect(run.out).to include("exit 1")
    expect(run.status).to eq(1)
    # The notice still reaches machine consumers through the JSON report.
    expect(run.json.fetch("warnings"))
      .to include(a_string_starting_with("inferred specs: running only spec/ledger_spec.rb"))
  end

  it "prints the notice on the same run without --quiet" do
    run = saboteur(dir, "--subject", "Ledger#record")

    expect(run.err).to include("inferred specs: running only spec/ledger_spec.rb. A spec that reaches a source file")
  end
end
