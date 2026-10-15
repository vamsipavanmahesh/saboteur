# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/dispatcher"

RSpec.describe Dispatcher do
  it "removes the build dir" do
    FileUtils.mkdir_p("build")
    File.write("build/out.txt", "x")
    Dispatcher.new.clean
    expect(Dir.exist?("build")).to be(false)
  end
end
