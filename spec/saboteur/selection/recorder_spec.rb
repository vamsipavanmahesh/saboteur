# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Selection::Recorder do
  it "carries the child-loaded sources and the build time into the built map (#353)" do
    map = described_class.new([]).result(build_seconds: 0.1, loaded_files: ["/app/support/helper.rb"])
    expect(map.loaded_files).to eq(["/app/support/helper.rb"])
    expect(map.build_seconds).to eq(0.1)
  end
end
