# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "yaml"

# How the coverage map cache is saved and shared.
RSpec.describe "coverage map cache wiring" do
  let(:root) { File.join(__dir__, "..", "..") }
  let(:action) { YAML.safe_load_file(File.join(root, "action.yml")) }
  let(:ci) { YAML.safe_load_file(File.join(root, ".github", "workflows", "ci.yml")) }
  let(:action_steps) { action.fetch("runs").fetch("steps") }
  let(:action_cache) { action_steps.find { |step| step["name"] == "Restore the coverage map" } }
  let(:action_save) { action_steps.find { |step| step["name"] == "Save the coverage map" } }
  let(:dogfood_steps) { ci.fetch("jobs").fetch("dogfood").fetch("steps") }
  let(:dogfood_restore) { dogfood_steps.find { |step| step["uses"].to_s.start_with?("actions/cache/restore@") } }
  let(:dogfood_save) { dogfood_steps.find { |step| step["uses"].to_s.start_with?("actions/cache/save@") } }

  def paths(step)
    step.fetch("with").fetch("path").split("\n")
  end

  it "restores and saves in separate steps, never with the deprecated save-always" do
    expect(action_cache.fetch("uses")).to start_with("actions/cache/restore@")
    expect(action_save.fetch("uses")).to start_with("actions/cache/save@")
    expect(action_steps.filter_map { |step| step["with"]&.key?("save-always") }).to be_empty
    expect(action_steps.filter_map { |step| step["uses"] }).to all(match(/\A[^@]+@[0-9a-f]{40}\z/))
  end

  it "saves after the run even when it failed, only where it restores, with the same key and paths" do
    expect(action_steps.index(action_save)).to be > action_steps.index { |step| step["id"] == "run" }
    expect(action_save.fetch("if")).to eq("always() && #{action_cache.fetch('if')}")
    expect(action_save.fetch("with").fetch("key")).to eq(action_cache.fetch("with").fetch("key"))
    expect(paths(action_save)).to eq(paths(action_cache))
    # The pointer rides with the map: without it a restored cache is never
    # read as whole-suite and pull requests lose the confirmation (#1317).
    expect(paths(action_cache)).to eq([".saboteur/coverage-*.json", ".saboteur/inputs-*.json",
                                       ".saboteur/whole-suite-map-v2"])
  end

  it "keeps the map fresh from the push/nightly dogfood with the action's key and paths" do
    expect(ci.fetch("jobs").fetch("dogfood").fetch("if")).to eq("github.event_name != 'workflow_dispatch'")
    expect(dogfood_restore.fetch("with").fetch("key")).to eq(action_cache.fetch("with").fetch("key"))
    expect(dogfood_restore.fetch("with").fetch("restore-keys")).to eq(action_cache.fetch("with").fetch("restore-keys"))
    expect(paths(dogfood_restore)).to eq(paths(action_cache))
    expect(paths(dogfood_save)).to eq(paths(action_cache))
    expect(dogfood_save.fetch("with").fetch("key")).to eq(action_cache.fetch("with").fetch("key"))
    # Save after the run even when it failed: a survivors-red run still
    # built a valid map.
    expect(dogfood_save.fetch("if")).to eq("always()")
    mutate = dogfood_steps.index { |step| step["name"] == "Mutate the changed methods" }
    expect(dogfood_steps.index(dogfood_save)).to be > mutate
    expect(dogfood_steps.filter_map { |step| step["uses"] }).to all(match(/\A[^@]+@[0-9a-f]{40}\z/))
  end

  it "checks out without persisting credentials" do
    checkout = dogfood_steps.find { |step| step["uses"].to_s.start_with?("actions/checkout@") }
    expect(checkout.fetch("with").fetch("persist-credentials")).to be(false)
  end
end
