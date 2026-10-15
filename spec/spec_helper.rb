# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "saboteur"
require "saboteur/cli"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |file| require file }

# Fixture repositories must not run Git background auto-maintenance: it
# deletes its own maintenance.lock while a spec removes the fixture tree,
# racing FileUtils.remove_entry (observed on macOS CI, #271).
ENV["GIT_CONFIG_COUNT"] = "1"
ENV["GIT_CONFIG_KEY_0"] = "maintenance.auto"
ENV["GIT_CONFIG_VALUE_0"] = "false"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :random
end
