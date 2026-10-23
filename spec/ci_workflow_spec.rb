# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "yaml"

# The ci-passed job is the single required check for ci.yml: branch
# protection and the panel gate wait on it instead of a fixed job list.
# These guards keep that indirection fail-closed: the aggregator must need
# every other job in the workflow (a new job not added to needs is ungated),
# and no other workflow may produce a check with the same name.
RSpec.describe "ci.yml ci-passed aggregator" do
  workflow_dir = File.expand_path("../.github/workflows", __dir__)

  it "needs every other job defined in ci.yml and always runs" do
    jobs = YAML.unsafe_load_file(File.join(workflow_dir, "ci.yml")).fetch("jobs")
    aggregator = jobs.fetch("ci-passed")
    expect(aggregator.fetch("if")).to eq("always()")
    expect(aggregator.fetch("needs")).to match_array(jobs.keys - ["ci-passed"])
  end

  it "is the only check named ci-passed across all workflows" do
    occurrences = Dir.glob(File.join(workflow_dir, "*.yml")).flat_map do |path|
      YAML.unsafe_load_file(path).fetch("jobs").filter_map do |id, job|
        File.basename(path) if id == "ci-passed" || job["name"] == "ci-passed"
      end
    end
    expect(occurrences).to eq(["ci.yml"])
  end

  it "runs one Linux Ruby 3.4 over the shards on pull request dispatches and the full matrix on push and nightly" do
    workflow = YAML.unsafe_load_file(File.join(workflow_dir, "ci.yml"))
    triggers = workflow.fetch("on", workflow[true])
    expect(triggers.fetch("schedule")).to eq([{ "cron" => "0 22 * * *" }])
    matrix = workflow.fetch("jobs").fetch("test").fetch("strategy").fetch("matrix")
    expect(matrix).to include("github.event_name == 'workflow_dispatch'")
    expect(matrix).to include('{"ruby":["3.4"],"shard":[1,2,3,4],"total":[4]}')
    expect(matrix).to include('{"ruby":["3.3","3.4","4.0","ruby"],"shard":[1,2,3,4],"total":[4]}')
  end

  it "ignore-audit proves the dispatch binding before it audits" do
    jobs = YAML.unsafe_load_file(File.join(workflow_dir, "ci.yml")).fetch("jobs")
    steps = jobs.fetch("ignore-audit").fetch("steps")
    binding = steps.index { |step| step["run"] == "script/ci-prove-pr-binding" }
    audit = steps.index { |step| step["name"] == "Audit ignore-file digest churn" }
    expect(binding).not_to be_nil
    expect(audit).not_to be_nil
    expect(binding).to be < audit
  end

  it "keeps the heavy legs off pull request dispatches and the PR-only audits on them" do
    jobs = YAML.unsafe_load_file(File.join(workflow_dir, "ci.yml")).fetch("jobs")
    %w[test-macos locale integration-gems dogfood].each do |job|
      expect(jobs.fetch(job).fetch("if")).to eq("github.event_name != 'workflow_dispatch'")
    end
    %w[ignore-audit dco].each do |job|
      expect(jobs.fetch(job).fetch("if")).to eq("github.event_name == 'workflow_dispatch'")
    end
    expect(jobs.keys).not_to include("warm-map")
  end

  it "aggregator skip table covers exactly the event-conditional jobs" do
    jobs = YAML.unsafe_load_file(File.join(workflow_dir, "ci.yml")).fetch("jobs")
    script = jobs.fetch("ci-passed").fetch("steps").first.fetch("run")
    table = script[/allowedSkip = \{(.*?)\}/m, 1]
    keys = table.scan(/"([^"]+)":/).flatten
    expect(keys).to match_array(%w[test-macos locale integration-gems dogfood ignore-audit dco])
  end
end
