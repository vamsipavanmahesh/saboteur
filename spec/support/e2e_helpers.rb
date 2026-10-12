# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# Runs the saboteur executable in a subprocess against a copy of a fixture
# project, the way a user would. The fixture is copied so the cache and the
# report land in a temp dir, never in the repository.
module E2EHelpers
  ROOT = File.expand_path("../..", __dir__)
  EXE = File.join(ROOT, "exe", "saboteur")
  Run = Data.define(:out, :err, :status, :json, :dir)

  def copy_fixture(name)
    dir = File.realpath(Dir.mktmpdir("saboteur-e2e-"))
    @e2e_dirs = (@e2e_dirs || []) << dir
    FileUtils.cp_r(File.join(ROOT, "spec", "fixtures", "projects", name, "."), dir)
    dir
  end

  def saboteur(dir, *, env: {})
    json_path = File.join(dir, ".saboteur", "report.json")
    FileUtils.rm_f(json_path)
    out, err, status = Open3.capture3(
      { "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile") }.merge(env),
      RbConfig.ruby, "-I", File.join(ROOT, "lib"), EXE, "run", *, chdir: dir
    )
    json = File.exist?(json_path) ? JSON.parse(File.read(json_path)) : nil
    Run.new(out:, err:, status: status.exitstatus, json:, dir:)
  end

  # { "Klass#meth" => { "operator" => status } } is too lossy when one
  # operator has several mutants, so return the full mutant list per file.
  def mutants(run)
    run.json.fetch("files").values.flat_map { |file| file.fetch("mutants") }
  end

  # What a failed exit-code expectation should print: stderr plus every mutant
  # the score could not count, so a resource-limit flake names its mutant.
  def unscored(run)
    return run.err unless run.json

    odd = mutants(run).reject { |m| %w[Killed Survived].include?(m["status"]) }
    details = odd.map { |m| m.slice("id", "status", "operator", "line").compact }
    "#{run.err}\nunscored mutants: #{details.inspect}"
  end

  # Full test names for the short ids a mutant's killedBy/coveredBy holds.
  def test_names(run, ids)
    names = run.json.fetch("testFiles").values.flat_map { |file| file.fetch("tests") }.to_h { |t| [t["id"], t["name"]] }
    ids.map { |id| names.fetch(id) }
  end
end

RSpec.configure do |config|
  config.include E2EHelpers, :e2e
  config.after(:each, :e2e) { (@e2e_dirs || []).each { |dir| FileUtils.rm_rf(dir) } }
end
