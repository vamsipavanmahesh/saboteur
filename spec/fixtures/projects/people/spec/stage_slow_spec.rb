# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/stage"

# Defined first and slow on purpose: with fastest-first ordering the quick
# test in stage_spec.rb must be the one that kills mutants.

require "fileutils"

# e2e evidence: a load of this file proves RSpec loaded it (saboteur --since scoping).
if ENV["SABOTEUR_E2E_TRACE"]
  FileUtils.mkdir_p(File.expand_path("../tmp", __dir__))
  File.open(File.expand_path("../tmp/loaded_specs.log", __dir__), "a") { |file| file.puts(File.basename(__FILE__)) }
end

RSpec.describe "Stage (slow)" do
  it "is adult at 50, slowly" do
    sleep 0.3
    expect(Stage.for(50)).to eq("adult")
  end
end
