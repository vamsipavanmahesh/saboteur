# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/sweeper"

RSpec.describe Sweeper do
  it "removes the generated dir" do
    FileUtils.mkdir_p("lib/generated")
    Sweeper.new.sweep
    expect(Dir.exist?("lib/generated")).to be(false)
  end
end
