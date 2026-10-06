# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur"
require "saboteur/cli"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :random
end
