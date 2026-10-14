# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"

%w[errors check_result command_runner strict_json safe_output options repository execution_inputs report
   runner].each do |file|
  require_relative file
end
Dir[File.join(__dir__, "checks", "*.rb")].each { |file| require file }
