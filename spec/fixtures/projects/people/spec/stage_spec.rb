# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/stage"

require "fileutils"

# e2e evidence: a load of this file proves RSpec loaded it (saboteur --since scoping).
if ENV["SABOTEUR_E2E_TRACE"]
  FileUtils.mkdir_p(File.expand_path("../tmp", __dir__))
  File.open(File.expand_path("../tmp/loaded_specs.log", __dir__), "a") { |file| file.puts(File.basename(__FILE__)) }
end

RSpec.describe Stage do
  it("is adult at 40") { expect(described_class.for(40)).to eq("adult") }
end
