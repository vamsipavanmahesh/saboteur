# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"

# The target's models specs run in process against sqlite. integration/patches/
# doorkeeper.patch moves the test database from memory to SAB_DB, so the
# per-mutant sandboxes share one on-disk file (hence --jobs 1 in targets.yml).
FileUtils.mkdir_p(File.dirname(ENV.fetch("SAB_DB")))

Saboteur.configure do |c|
  c.include = %w[
    lib/doorkeeper/models/access_token_mixin.rb
    lib/doorkeeper/models/application_mixin.rb
    lib/doorkeeper/models/access_grant_mixin.rb
  ]
  c.tests = %w[spec/models]
  c.jobs = 1
  c.baseline_passes = 1
  c.coverage_recorder = ENV.fetch("SABOTEUR_COVERAGE_RECORDER", "coverage")
  c.sandbox_writable = [File.dirname(ENV.fetch("SAB_DB"))]
end
