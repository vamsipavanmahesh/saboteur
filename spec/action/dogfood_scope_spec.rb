# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "yaml"

# The dogfood job runs on pushes to main and on the nightly schedule. It
# resolves its diff base first (the pushed range, or the last 24 hours of
# main commits), then no-ops green on diffs with nothing to mutate
# instead of dying on the out-of-scope stop (#483, exit 2): config-only
# diffs and version-only diffs, because config/saboteur.rb excludes
# lib/saboteur/version.rb from mutation (#1084). The pull-request
# binding proof moved to the ignore-audit job; spec/ci_workflow_spec.rb
# pins that it runs there before the audit.
RSpec.describe "dogfood scope detection" do
  let(:root) { File.join(__dir__, "..", "..") }
  let(:ci) { YAML.safe_load_file(File.join(root, ".github", "workflows", "ci.yml")) }
  let(:dogfood_steps) { ci.fetch("jobs").fetch("dogfood").fetch("steps") }
  let(:base_step) { dogfood_steps.find { |step| step["id"] == "base" } }
  let(:scope_step) { dogfood_steps.find { |step| step["id"] == "scope" } }
  let(:mutate_step) { dogfood_steps.find { |step| step["name"] == "Mutate the changed methods" } }
  let(:artifact_step) { dogfood_steps.find { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") } }
  let(:script) { scope_step.fetch("run") }

  it "resolves the diff base, then detects the scope, then mutates" do
    expect(dogfood_steps.index(base_step)).to be < dogfood_steps.index(scope_step)
    expect(dogfood_steps.index(scope_step)).to be < dogfood_steps.index(mutate_step)
  end

  it "takes the base from the resolved step output, never straight from an input" do
    expect(scope_step.dig("env", "BASE_SHA")).to eq("${{ steps.base.outputs.sha }}")
    expect(mutate_step.dig("env", "BASE_SHA")).to eq("${{ steps.base.outputs.sha }}")
    expect(script).to include('git diff --quiet "$BASE_SHA" HEAD -- "lib/*.rb"')
    expect(script).to include("config-only diff")
  end

  it "no-ops green when the only changed lib file is the mutation-excluded version.rb" do
    expect(script).to include("git diff --name-only")
    expect(script).to include("grep -vx 'lib/saboteur/version.rb'")
  end

  it "marks the diff empty so the mutate and artifact steps skip it" do
    expect(script.scan('echo "empty=true" >> "$GITHUB_OUTPUT"').size).to eq(2)
    expect(mutate_step.fetch("if")).to eq("steps.scope.outputs.empty != 'true'")
    expect(artifact_step.fetch("if")).to include("steps.scope.outputs.empty != 'true'")
  end

  it "keeps the version.rb exclusion in config/saboteur.rb that the guard mirrors" do
    config = File.read(File.join(root, "config", "saboteur.rb"))
    expect(config).to include('"lib/saboteur/version.rb"')
  end
end
