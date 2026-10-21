# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# README: "--shard K/N splits one planned inventory deterministically across
# CI jobs." Two halves of the people fixture must be disjoint, must cover
# the whole unsharded inventory, and must repeat identically.
require "support/e2e_helpers"

RSpec.describe "--shard K/N", :e2e do
  include E2EHelpers

  def digests(run)
    mutants(run).map { |m| m["id"] }
  end

  it "splits the inventory disjointly and completely" do
    dir = copy_fixture("people")
    first = saboteur(dir, "--shard", "1/2")
    second = saboteur(dir, "--shard", "2/2")
    whole = saboteur(dir)

    half1 = digests(first)
    half2 = digests(second)
    expect(half1 & half2).to be_empty
    expect(half1 | half2).to match_array(digests(whole))
  end

  it "repeats the same split" do
    dir = copy_fixture("people")
    expect(digests(saboteur(dir, "--shard", "1/2"))).to eq(digests(saboteur(dir, "--shard", "1/2")))
  end
end
