# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/cleaner"

RSpec.describe Cleaner do
  it "removes the logs dir" do
    FileUtils.mkdir_p(".saboteur/logs")
    Cleaner.new.purge
    expect(Dir.exist?(".saboteur/logs")).to be(false)
  end
end
