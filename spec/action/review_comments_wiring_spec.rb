# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "yaml"

# How action.yml wires action/post-review-comments (#246).
RSpec.describe "action.yml review comments" do
  let(:action) { YAML.safe_load_file(File.join(__dir__, "..", "..", "action.yml")) }
  let(:inputs) { action.fetch("inputs") }
  let(:steps) { action.fetch("runs").fetch("steps") }
  let(:step) { steps.find { |candidate| candidate["name"] == "Comment surviving mutants on the pull request" } }

  it "is off by default, capped at ten, and takes its token from an input" do
    expect(inputs.fetch("review-comments")).to include("required" => false, "default" => "false")
    expect(inputs.fetch("max-comments")).to include("required" => false, "default" => "10")
    expect(inputs.fetch("github-token")).to include("required" => false, "default" => "${{ github.token }}")
    expect(inputs.fetch("bot-login")).to include("required" => false, "default" => "github-actions[bot]")
  end

  it "runs only when asked for, on a pull_request, after a trusted report" do
    expect(step.fetch("if")).to eq("always() && inputs.review-comments == 'true' && " \
                                   "github.event_name == 'pull_request' && steps.run.outputs.report-valid == 'true'")
  end

  it "never fails the job" do
    expect(step.fetch("continue-on-error")).to be(true)
  end

  it "reaches the script only through environment variables" do
    expect(step.fetch("env")).to eq(
      "GH_TOKEN" => "${{ inputs.github-token }}",
      "SABOTEUR_EVENT_NAME" => "${{ github.event_name }}",
      "SABOTEUR_REPORT_PATH" => "${{ inputs.report-path }}",
      "SABOTEUR_PR_NUMBER" => "${{ github.event.pull_request.number }}",
      "SABOTEUR_HEAD_SHA" => "${{ github.event.pull_request.head.sha }}",
      "SABOTEUR_HEAD_REPO" => "${{ github.event.pull_request.head.repo.full_name }}",
      "SABOTEUR_MAX_COMMENTS" => "${{ inputs.max-comments }}",
      "SABOTEUR_BOT_LOGIN" => "${{ inputs.bot-login }}",
      "SABOTEUR_RUN_URL" => "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
    )
    expect(step.fetch("run")).to eq('ruby "${{ github.action_path }}/action/post-review-comments"')
    expect(step.fetch("run")).not_to include("inputs.")
  end

  it "runs after the saboteur step, whose report it reads" do
    names = steps.map { |candidate| candidate["id"] || candidate["name"] }

    expect(names.index("run")).to be < names.index("Comment surviving mutants on the pull request")
  end

  it "points at a script that exists and is executable" do
    script = File.expand_path("../../action/post-review-comments", __dir__)

    expect(File.executable?(script)).to be(true)
  end
end
