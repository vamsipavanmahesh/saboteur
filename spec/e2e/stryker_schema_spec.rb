# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json_schemer"

# Locks review issue #127: every JSON report validates against the official
# Stryker mutation-testing report schema (draft-07, vendored from
# stryker-mutator/mutation-testing-elements, Apache-2.0).
RSpec.describe "report.json against the Stryker schema (end to end)", :e2e do
  schema_path = File.join(E2EHelpers::ROOT, "spec/fixtures/schemas/mutation-testing-report-schema.json")
  schemer = JSONSchemer.schema(JSON.parse(File.read(schema_path)))

  %w[people endless shapes orderdep hazards].each do |fixture|
    it "validates the report of the #{fixture} fixture, whatever mix of statuses it holds" do
      run = saboteur(copy_fixture(fixture), "--all")
      expect(run.json).not_to be_nil, run.err
      errors = schemer.validate(run.json).map { |error| error.fetch("error") }
      expect(errors).to be_empty
    end
  end

  it "rejects a report with a status the schema does not know, so the check can fail" do
    report = saboteur(copy_fixture("endless"), "--all").json
    report["files"].values.first["mutants"].first["status"] = "Exploded"
    expect(schemer.valid?(report)).to be(false)
  end
end
