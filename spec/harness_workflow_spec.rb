# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "yaml"

# Structural pins for .github/workflows/harness.yml: the full acceptance
# tier is the release gate, so the workflow must never run it silently,
# skip it silently, or let the fast tier masquerade as a full run.
RSpec.describe ".github/workflows/harness.yml" do
  let(:workflow) { YAML.load_file(File.expand_path("../.github/workflows/harness.yml", __dir__)) }
  # YAML 1.1 parses the bare `on:` key as boolean true.
  let(:triggers) { workflow.fetch("on", workflow[true]) }
  let(:steps) { workflow.dig("jobs", "acceptance", "steps") }

  it "offers the full tier only as an explicit, validated dispatch choice" do
    tier = triggers.dig("workflow_dispatch", "inputs", "tier")
    expect(tier["type"]).to eq("choice")
    expect(tier["options"]).to eq(%w[fast full])
    expect(tier["required"]).to be(true)
    expect(tier["default"]).to eq("fast")
  end

  it "keeps push and pull_request on the fast tier only" do
    expect(triggers["push"]).to eq("branches" => ["main"])
    expect(triggers["pull_request"]).to eq("branches" => ["main"])
    fast = steps.find { |s| s["run"] == "bundle exec rake acceptance:fast" }
    full = steps.find { |s| s["run"] == "bundle exec rake acceptance" }
    # push/pull_request events carry no inputs, so the full step's
    # condition can never be met there.
    expect(fast["if"]).to eq("github.event.inputs.tier != 'full'")
    expect(full["if"]).to eq("github.event.inputs.tier == 'full'")
  end

  it "cannot masquerade: the full-gated step runs the full harness task, read-only, no publish" do
    full = steps.find { |s| s["if"] == "github.event.inputs.tier == 'full'" }
    expect(full["run"]).to eq("bundle exec rake acceptance")
    expect(workflow["permissions"]).to eq("contents" => "read")
    expect(YAML.dump(workflow)).not_to include("secrets.")
  end
end
