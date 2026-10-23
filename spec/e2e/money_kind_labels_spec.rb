# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The kind-first label end to end (#1314): the real binary runs against a tmp
# project carrying the vendored money allocation (byte-identical to
# money v6.19.0, see fixtures/projects/money_ranking/UPSTREAM.txt; upstream's
# parts_sum > 0 comparison sits at line 52 there, line 40 in the vendored
# file). The comparison's group shows the kind first with the observed gap
# appended, unknown-gap groups show the kind alone, and no header ever says
# "coarse". JSON keeps classification and gapKind unchanged and adds kind
# only where a check is really missing - never on a killed mutant.
RSpec.describe "money allocation kind labels (end to end)", :e2e do
  let(:dir) { copy_fixture("money_kind") }

  it "shows the kind first with the observed gap, the kind alone when the gap is unknown, and adds kind to the JSON" do
    run = saboteur(dir, "--all")
    expect(run.status).to eq(1), other_outcomes(run)

    comparison = mutants(run).select do |m|
      m["mutatorName"] == "comparison" && m.dig("location", "start", "line") == 40
    end
    survivors = comparison.select { |m| m["status"] == "Survived" }
    expect(survivors).not_to be_empty, "expected the parts_sum > 0 comparison to survive under positive-only parts"
    survivors.each do |m|
      expect(m.values_at("classification", "gapKind", "kind")).to eq(%w[input_gap boundary boundary])
    end
    # Killed mutants never gain a kind: no check is missing once a test catches the mutant.
    mutants(run).select { |m| m["status"] == "Killed" }.each { |m| expect(m).not_to have_key("kind") }

    # The line-40 group shows the kind first with the observed gap appended;
    # the covered-but-not-value-probed line-27 group and a plain effect group show the kind alone;
    # no header ever says "coarse".
    expect(run.out).to include("[branch · assertion gap ·")
    expect(run.out).to include("[result unchecked ·")
    expect(run.out).to include("[effect ·")
    expect(run.out).not_to include("[coarse")
  end
end
