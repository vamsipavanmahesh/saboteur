# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "yaml"

# How action.yml wires action/fetch-base (#786).
RSpec.describe "action.yml base fetch" do
  let(:action) { YAML.safe_load_file(File.join(__dir__, "..", "..", "action.yml")) }
  let(:steps) { action.fetch("runs").fetch("steps") }
  let(:names) { steps.map { |candidate| candidate["name"] } }
  let(:fetch_step) { steps.find { |candidate| candidate["name"] == "Fetch the pull request base" } }
  let(:run_step) { steps.find { |candidate| candidate["name"] == "Mutate the changed methods" } }

  it "runs before the step that runs the pull request's tests" do
    expect(names.index("Fetch the pull request base")).to be < names.index("Mutate the changed methods")
  end

  it "gives the token to the fetch step alone, never to the step that runs the tests" do
    holders = steps.select { |step| step.fetch("env", {}).values.any? { |value| value.include?("github-token") } }

    expect(fetch_step.fetch("env")).to include("SABOTEUR_FETCH_TOKEN" => "${{ inputs.github-token }}")
    expect(holders.map { |step| step["name"] }).to eq(["Fetch the pull request base",
                                                       "Comment surviving mutants on the pull request"])
    expect(run_step.fetch("env").keys).not_to include(a_string_matching(/TOKEN/))
  end

  it "never fails the job, and skips baseline runs and other events like the run step" do
    expect(fetch_step.fetch("continue-on-error")).to be(true)
    expect(fetch_step.fetch("if")).to eq("inputs.baseline == '' && (github.event_name == 'pull_request' || " \
                                         "github.event_name == 'workflow_dispatch')")
    expect(fetch_step.fetch("run")).to eq('bash "${{ github.action_path }}/action/fetch-base"')
  end

  it "passes the script only the event, the base commit and the token" do
    expect(fetch_step.fetch("env").keys).to contain_exactly("SABOTEUR_FETCH_TOKEN", "SABOTEUR_EVENT_NAME",
                                                            "SABOTEUR_BASE_SHA")
  end
end
