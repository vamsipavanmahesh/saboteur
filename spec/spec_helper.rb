# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "rbconfig"

# Run the environment gate once per suite process (AGENTS.md, "Run
# discipline"): a bare `bundle exec rspec` bypasses the rake tasks and
# script/rspec-shard, so the suite itself refuses to run on a red toolchain.
# Skipped inside saboteur's own test-run children (SABOTEUR_CHILD from the
# supervisor, SABOTEUR_EXTERNAL_CHILD from the external runner): when
# saboteur dogfoods this repo, every mutated child would rerun the gate and
# a gate abort would be credited as a mutant kill. The parent run checks
# the environment before spawning children.
unless ENV["SABOTEUR_CHILD"] || ENV["SABOTEUR_EXTERNAL_CHILD"] ||
       system(RbConfig.ruby, File.expand_path("../bin/check-env", __dir__), chdir: File.expand_path("..", __dir__))
  abort "check-env failed; fix the environment before running the suite"
end

require "saboteur"
require "saboteur/cli"

# The palette colours output on a known colour-capable CI (GITHUB_ACTIONS)
# in auto mode; rendering specs must not depend on the ambient environment,
# so the suite drops the key. Palette detection specs pass an explicit
# environment: hash instead.
ENV.delete("GITHUB_ACTIONS")

# The specs call the sandbox layers (Sandbox, Seatbelt, LibC) directly and
# run in any order, so a file can touch Fiddle before any code path has gone
# through the lazy door (#697) - cold NameError flakes on CI shards. Load
# fiddle once up front through the one guarded door (#639): the door stays
# lazy in production, the suite stops depending on example order.
Saboteur::Execution::FiddleLoader.require_fiddle!(with_import: true)

# Engine doubles flowing through text_run must carry the coverage-map
# readers run_reporting asks of the engine (review C1): every Engine double
# gets nil maps and a cache-less lookup unless the example overrides them.
def engine_double(**kwargs)
  instance_double(Saboteur::Engine,
                  { whole_suite_coverage_map: nil, run_coverage_map: nil,
                    whole_suite_map_lookup?: false }.merge(kwargs))
end

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |file| require file }

# Fixture repositories must not run Git background auto-maintenance: it
# deletes its own maintenance.lock while a spec removes the fixture tree,
# racing FileUtils.remove_entry (observed on macOS CI, #271).
# Append to any inherited GIT_CONFIG_* block instead of replacing it (#289).
git_config_index = ENV["GIT_CONFIG_COUNT"].to_i
ENV["GIT_CONFIG_KEY_#{git_config_index}"] = "maintenance.auto"
ENV["GIT_CONFIG_VALUE_#{git_config_index}"] = "false"
ENV["GIT_CONFIG_COUNT"] = (git_config_index + 1).to_s

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :random
end
