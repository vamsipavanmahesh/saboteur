# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/cleaner"

RSpec.describe Cleaner do
  it "sums the prices" do
    expect(Cleaner.new.total([1, 2, 3])).to eq(6)
  end

  it "removes the trash dir" do
    FileUtils.mkdir_p(".saboteur/trash")
    Cleaner.new.purge
    expect(Dir.exist?(".saboteur/trash")).to be(false)
  end
end
