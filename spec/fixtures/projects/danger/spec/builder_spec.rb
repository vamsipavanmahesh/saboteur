# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/builder"

RSpec.describe Builder do
  it "removes the build dir" do
    FileUtils.mkdir_p("build")
    File.write("build/out.txt", "x")
    Builder.new.clean
    expect(Dir.exist?("build")).to be(false)
  end
end
