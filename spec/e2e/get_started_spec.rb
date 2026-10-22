# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

# README "Get started in 3 steps": step 2 is "bundle exec saboteur run (the
# first run builds a cached coverage map)", step 3 is "bundle exec saboteur pr
# (mutates only what you changed vs main)". Step 1 is a plain `bundle add`.
# The project has no config file, as in a fresh install.
RSpec.describe "the README get-started flow (end to end)", :e2e do
  let(:dir) do
    copy_fixture("people").tap { |copy| FileUtils.rm_rf(File.join(copy, "config")) }
  end

  def git(*args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    raise err unless status.success?
  end

  def mutated_files(run)
    run.json.fetch("files").keys.map { |path| File.basename(path) }
  end

  it "step 2: the first run builds the coverage map and the second run reuses it" do
    first = saboteur(dir)
    expect(first.err).to include("no config/saboteur.rb - using defaults")
    expect(first.err).to include("coverage cache miss: no earlier map to compare with")
    expect(first.err).to include("coverage map: 6 tests")
    expect(first.err).not_to include("(cached)")
    expect(mutated_files(first)).to contain_exactly("people.rb", "stage.rb")

    second = saboteur(dir)
    expect(second.err).to include("coverage map: 6 tests (cached)")
    expect(second.err).not_to include("coverage cache miss")
  end

  it "step 2 under --quiet: the first run keeps stderr free of first-run notices (#1264)" do
    first = saboteur(dir, "--quiet")
    expect(first.err).not_to include("no config/saboteur.rb")
    expect(first.err).not_to include("coverage cache miss")
    expect(first.err).not_to include("building coverage map")
    # The one kept notice: a correctness caveat about how specs were chosen.
    expect(first.err.lines.map(&:strip).reject(&:empty?))
      .to match([start_with("saboteur: inferred specs: selected by constant reference or require")])
  end

  it "step 3: pr mutates only what changed against main" do
    git("init", "-q")
    git("checkout", "-q", "-b", "main")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    git("checkout", "-q", "-b", "feature")
    path = File.join(dir, "lib", "people.rb")
    File.write(path, File.read(path).sub("@age}\"", "@age.to_s}\""))
    git("commit", "-q", "-a", "-m", "change")

    run = saboteur(dir, "pr", command: nil)

    expect(run.status).to eq(0), other_outcomes(run)
    expect(run.err).to include("preset 'pr':", "--since main")
    expect(run.out).to include("4/4 mutants killed")
    expect(mutated_files(run)).to eq(["people.rb"])
    changed_line = File.readlines(path).index { |line| line.include?("@age.to_s") } + 1
    expect(mutants(run).map { |m| m.dig("location", "start", "line") }.uniq).to eq([changed_line])
  end
end
