# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "yaml"
require "saboteur/install"

# `saboteur install` writes the two CI workflows for the whole-suite map (#1317).
RSpec.describe Saboteur::Install, "CI workflows" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:action) { YAML.safe_load_file(File.expand_path("../../action.yml", __dir__)) }
  let(:map_file) { ".github/workflows/saboteur-map.yml" }
  let(:pr_file) { ".github/workflows/saboteur-pr.yml" }

  def workflows(**) = described_class.new(root: @root, **).ci_workflows
  def read(path) = File.read(File.join(@root, path))
  def parsed(path) = YAML.safe_load(read(path), aliases: false)
  def step(workflow, name) = workflow.dig("jobs", workflow["jobs"].keys.first, "steps").find { |s| s["name"] == name }
  def action_step(name) = action.dig("runs", "steps").find { |s| s["name"] == name }

  it "writes both workflow files and reports what it wrote" do
    results = workflows
    expect(results.map { |r| [r.status, r.path] }).to eq([[:created, map_file], [:created, pr_file]])
    expect(parsed(map_file)).to include("name" => "Saboteur map")
    expect(parsed(pr_file)).to include("name" => "Saboteur")
  end

  it "never overwrites an existing workflow file, even with force" do
    FileUtils.mkdir_p(File.join(@root, ".github/workflows"))
    File.write(File.join(@root, map_file), "mine\n")
    results = workflows(force: true)
    expect(results.map { |r| [r.status, r.path] }).to eq([[:skipped, map_file], [:created, pr_file]])
    expect(read(map_file)).to eq("mine\n")
  end

  it "never writes through a symlinked .github directory" do
    elsewhere = Dir.mktmpdir
    File.symlink(elsewhere, File.join(@root, ".github"))
    expect(workflows.map(&:status)).to eq(%i[skipped skipped])
    expect(Dir.children(elsewhere)).to be_empty
  ensure
    FileUtils.rm_rf(elsewhere)
  end

  describe "the main workflow" do
    let(:workflow) { workflows && parsed(map_file) }

    it "builds the map on pushes to main with the whole-suite run, tolerating survivors only" do
      expect(workflow.fetch(true).fetch("push")).to eq("branches" => ["main"])
      run = step(workflow, "Build the whole-suite map").fetch("run")
      expect(run).to include("bundle exec saboteur run --all")
      expect(run).to include('[ "$status" -le 1 ] || exit "$status"')
    end

    it "saves the map even when the run found survivors, and only when a map exists" do
      save = step(workflow, "Save the map")
      expect(save.fetch("if")).to eq("always() && hashFiles('.saboteur/whole-suite-map-v2') != ''")
    end
  end

  describe "the cache scheme shared with the action" do
    let(:workflow) { workflows && parsed(map_file) }
    let(:saved) { step(workflow, "Save the map").fetch("with") }
    let(:restored) { action_step("Restore the coverage map").fetch("with") }

    it "saves under the key the action restores from, and under the action's own save path" do
      expect(saved.fetch("key")).to eq(restored.fetch("key"))
      expect(saved.fetch("path")).to eq(restored.fetch("path"))
      expect(action_step("Save the coverage map").dig("with", "path")).to eq(restored.fetch("path"))
    end

    it "restores the pointer to the whole-suite map, without which the map is not read as whole-suite" do
      expect(restored.fetch("path").split("\n")).to include(".saboteur/whole-suite-map-v2")
    end

    it "lets a pull request find the latest main map by the action's restore prefix" do
      prefix = restored.fetch("restore-keys").strip
      expect(saved.fetch("key")).to start_with(prefix)
    end
  end

  describe "the pull request workflow" do
    let(:workflow) { workflows && parsed(pr_file) }
    let(:uses) do
      workflow.dig("jobs", "mutation", "steps").find do |s|
        s["uses"].to_s.start_with?("vamsipavanmahesh/saboteur@")
      end
    end

    it "runs the saboteur action in the settings of `saboteur pr` and posts review comments" do
      expect(workflow.fetch(true)).to eq("pull_request")
      expect(workflow.fetch("permissions")).to eq("contents" => "read", "pull-requests" => "write")
      expect(uses.fetch("with")).to eq("arguments" => "--baseline-passes 1", "max-duration" => "10m",
                                       "review-comments" => "true")
    end

    it "leaves the action's cache on, so it restores the map the main workflow saved" do
      expect(uses.fetch("with")).not_to have_key("cache")
    end
  end

  # The generated files are pinned byte for byte: a YAML parse cannot see a
  # mutated comment, trigger, permission or cache line that still parses.
  describe "the exact generated text" do
    it "writes the main-map workflow verbatim" do
      workflows
      expect(read(map_file)).to eq(<<~YAML)
        # Builds the whole-suite coverage map on main so pull requests can confirm
        # survivors against specs they did not load. Written by `saboteur install`.
        name: Saboteur map
        on:
          push:
            branches: [main]
          workflow_dispatch:
          # schedule:
          #   - cron: "17 3 * * 1"
        permissions:
          contents: read
        jobs:
          map:
            runs-on: ubuntu-latest
            timeout-minutes: 120
            steps:
              - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
                with:
                  fetch-depth: 1
              - uses: ruby/setup-ruby@14594264cd68ce8a2345dd349bc3d138a4ef85c8 # v1
                with:
                  ruby-version: "3.3"
                  bundler-cache: true
              # Add your database, services and any other setup your specs need here.
              - name: Build the whole-suite map
                run: |
                  status=0
                  bundle exec saboteur run --all || status=$?
                  # Exit 1 means survivors: the map is still built and saved below.
                  [ "$status" -le 1 ] || exit "$status"
              - name: Save the map
                if: always() && hashFiles('.saboteur/whole-suite-map-v2') != ''
                uses: actions/cache/save@0057852bfaa89a56745cba8c7296529d2fc39830 # v4
                with:
                  path: |
                    .saboteur/coverage-*.json
                    .saboteur/inputs-*.json
                    .saboteur/whole-suite-map-v2
                  key: saboteur-${{ runner.os }}-${{ hashFiles('Gemfile.lock', 'config/saboteur.rb', 'config/saboteur_custom_map.rb', 'config/saboteur_ignore.rb') }}-${{ github.sha }}
      YAML
    end

    it "writes the pull-request workflow verbatim" do
      workflows
      expect(read(pr_file)).to eq(<<~YAML)
        # Mutates the lines a pull request changed and comments the survivors. The
        # action restores the map the main workflow saved. Written by `saboteur install`.
        name: Saboteur
        on: pull_request
        permissions:
          contents: read
          pull-requests: write
        jobs:
          mutation:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
                with:
                  fetch-depth: 1
              - uses: ruby/setup-ruby@14594264cd68ce8a2345dd349bc3d138a4ef85c8 # v1
                with:
                  ruby-version: "3.3"
                  bundler-cache: true
              # Add your database, services and any other setup your specs need here.
              # Pin this to a release tag once one contains the whole-suite map cache.
              - uses: vamsipavanmahesh/saboteur@main
                with:
                  # The settings of `saboteur pr`: one baseline check, a 10 minute budget.
                  arguments: --baseline-passes 1
                  max-duration: 10m
                  review-comments: "true"
      YAML
    end
  end

  it "also leaves the Ruby version to the project's .tool-versions" do
    File.write(File.join(@root, ".tool-versions"), "ruby 3.4.1\n")
    workflows
    expect(read(map_file)).not_to include("ruby-version:")
    expect(read(pr_file)).not_to include("ruby-version:")
  end

  it "leaves the Ruby version to the project's .ruby-version when there is one" do
    File.write(File.join(@root, ".ruby-version"), "3.4.1\n")
    workflows
    expect(read(map_file)).not_to include("ruby-version:")
    expect(read(pr_file)).not_to include("ruby-version:")
  end

  it "names a Ruby version when the project pins none" do
    workflows
    expect(read(map_file)).to include('ruby-version: "3.3"')
  end
end
