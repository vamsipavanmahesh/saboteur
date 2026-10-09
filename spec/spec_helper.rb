# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "saboteur"
require "saboteur/cli"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |file| require file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :random
end
