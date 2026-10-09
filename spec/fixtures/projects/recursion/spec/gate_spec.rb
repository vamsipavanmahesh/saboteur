# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "saboteur/cli"
require_relative "../lib/gate"

RSpec.describe Gate do
  it "keeps the gate shut for zero jobs, so no run starts" do
    outcome = Gate.open?(0) ? Saboteur::CLI.new(["run"], out: StringIO.new, err: StringIO.new).call : :shut
    expect(outcome).to eq(:shut)
  end

  it "opens for one job" do
    expect(Gate.open?(1)).to be(true)
  end
end
