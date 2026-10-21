# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The money-gem ranking regression (#1160): the review's remainder finding
# (#1144) - several surviving mutants on one barely-tested statement - must
# rank in the top 2, ahead of a survivor on a well-covered statement.
require "support/e2e_helpers"

RSpec.describe "survivor ranking (money-style fixture)", :e2e do
  include E2EHelpers

  it "ranks the remainder finding in the top 2, ahead of the well-covered split line" do
    run = saboteur(copy_fixture("moneylike"))

    expect(run.status).to eq(1), run.out + run.err
    survivors = run.json.dig("saboteur", "findings", "survivors")
    remainder = survivors.index { |s| s["subject"] == "Allocation#remainder" }
    split = survivors.index { |s| s["subject"] == "Allocation#split" }
    expect(remainder).to be < 2
    expect(remainder).to be < split
  end
end
