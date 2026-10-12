# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../support/e2e_helpers"

RSpec.describe E2EHelpers, "#unscored" do
  subject(:helper) { Object.new.extend(described_class) }

  def run_with(mutants, err: "boom")
    json = { "files" => { "lib/a.rb" => { "mutants" => mutants } } }
    described_class::Run.new(out: "", err:, status: 3, json:, dir: "/tmp")
  end

  it "names the mutator, line, status and reason of every mutant the score could not count" do
    run = run_with([
                     { "id" => "k1", "status" => "Killed", "mutatorName" => "x" },
                     { "id" => "e1", "status" => "RuntimeError", "mutatorName" => "NegateCondition",
                       "location" => { "start" => { "line" => 12, "column" => 4 } },
                       "statusReason" => "resource limit: memory" }
                   ])
    message = helper.unscored(run)
    expect(message).to include("boom", "e1", "RuntimeError", "NegateCondition", "12", "resource limit: memory")
    expect(message).not_to include("k1")
  end

  it "falls back to stderr when no report was written" do
    run = described_class::Run.new(out: "", err: "no report", status: 2, json: nil, dir: "/tmp")
    expect(helper.unscored(run)).to eq("no report")
  end
end
