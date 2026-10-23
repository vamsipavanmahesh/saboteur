# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "yaml"

# #1317: `saboteur install` writes the CI workflows, and the map the main
# workflow saves is the one a pull request run confirms survivors against. The
# cache is simulated the way Actions does it: the pull request job checks
# out at the same path the main job used (the map keys files by realpath),
# and only the files the save step's path globs match survive the restore.
RSpec.describe "saboteur install and the whole-suite map in CI (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  def git(*args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    raise err unless status.success?
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  def install(*args, in_dir: dir)
    root = E2EHelpers::ROOT
    out, err, status = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(root, "Gemfile") },
                                      RbConfig.ruby, "-I", File.join(root, "lib"), E2EHelpers::EXE, "install", *args,
                                      chdir: in_dir)
    [out, err, status.exitstatus]
  end

  def saved_paths
    workflow = YAML.safe_load_file(File.join(dir, ".github/workflows/saboteur-map.yml"))
    workflow.dig("jobs", "map", "steps").find { |step| step["name"] == "Save the map" }.dig("with", "path").split("\n")
  end

  it "writes both workflows, says what it wrote and the next step, and leaves existing files alone" do
    out, err, status = install
    expect(status).to eq(0), err
    expect(out).to include("created  .github/workflows/saboteur-map.yml", "created  .github/workflows/saboteur-pr.yml")
    expect(out).to include("Next: commit both files and push to main")

    File.write(File.join(dir, ".github/workflows/saboteur-pr.yml"), "mine\n")
    out, = install
    expect(out).to include("skipped  .github/workflows/saboteur-map.yml (already there, left as it is)")
    expect(out).not_to include("Next:")
    expect(File.read(File.join(dir, ".github/workflows/saboteur-pr.yml"))).to eq("mine\n")
  end

  context "with a map built on main and restored on a pull request" do
    before do
      write("lib/ledger/router.rb", <<~RUBY)
        module Ledger
          class Router
            def lane(amount) = amount > 5_000_000 ? "review" : "auto"
          end
        end
      RUBY
      write("spec/ledger/router_spec.rb", <<~RUBY)
        require_relative "../../lib/ledger/router"

        RSpec.describe Ledger::Router do
          it("answers a lane") { expect(described_class.new.lane(10)).to be_a(String) }
        end
      RUBY
      write("spec/integration/flow_spec.rb", <<~RUBY)
        require_relative "../../lib/ledger/router"

        RSpec.describe "payment flow" do
          it("sends large amounts to review") { expect(Ledger::Router.new.lane(6_000_000)).to eq("review") }
          it("keeps the limit itself automatic") { expect(Ledger::Router.new.lane(5_000_000)).to eq("auto") }
        end
      RUBY
      install
      git("init", "-q")
      git("add", ".")
      git("commit", "-q", "-m", "base")
      write("lib/ledger/router.rb",
            File.read(File.join(dir, "lib/ledger/router.rb")).sub("> 5_000_000", ">= 5_000_001"))
      saboteur(dir, "--all")
    end

    # A restore keeps only what the save step's path globs match, the same
    # way the Actions cache drops everything else in .saboteur.
    def restore(globs)
      kept = globs.flat_map { |glob| Dir[File.join(dir, glob)] }
      stash = Dir.mktmpdir("saboteur-e2e-stash-")
      (@e2e_dirs ||= []) << stash
      kept.each { |path| FileUtils.mv(path, stash) }
      FileUtils.rm_rf(File.join(dir, ".saboteur"))
      FileUtils.mkdir_p(File.join(dir, ".saboteur"))
      Dir[File.join(stash, "*")].each { |path| FileUtils.mv(path, File.join(dir, ".saboteur")) }
    end

    it "lets the pull request run confirm survivors against the saved map" do
      restore(saved_paths)
      run = saboteur(dir, "--since", "HEAD")
      expect(run.err).not_to include("survivors unconfirmed")
      killed = mutants(run).select { |mutant| mutant["confirmation"] == "killed_by_confirmation" }
      expect(killed.size).to eq(9)
    end

    it "leaves survivors unconfirmed when the pointer is not part of the saved paths" do
      restore(saved_paths - [".saboteur/whole-suite-map-v2"])
      run = saboteur(dir, "--since", "HEAD")
      expect(run.err).to include("survivors unconfirmed")
    end
  end
end
