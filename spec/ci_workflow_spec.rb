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
end
