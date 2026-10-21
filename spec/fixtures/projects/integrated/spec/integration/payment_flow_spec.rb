# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../../lib/ledger"

require "fileutils"

# e2e evidence: a load of this file proves RSpec loaded it (saboteur --since scoping).
if ENV["SABOTEUR_E2E_TRACE"]
  FileUtils.mkdir_p(File.expand_path("../../tmp", __dir__))
  File.open(File.expand_path("../../tmp/loaded_specs.log", __dir__), "a") { |file| file.puts(File.basename(__FILE__)) }
end

RSpec.describe "the payment flow" do
  it "doubles a small amount" do
    expect(Ledger.new.fee(2)).to eq(4)
  end

  it "doubles a larger amount" do
    expect(Ledger.new.fee(5)).to eq(10)
  end
end
