# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# README ("Built for big suites"): "--shard K/N splits one planned
# inventory deterministically across CI jobs."
RSpec.describe "saboteur run --shard (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  def scoped_args
    ["lib/people.rb", "--test", "spec/person_spec.rb"]
  end

  it "splits the planned inventory into disjoint shards whose union is the full run" do
    full = saboteur(dir, *scoped_args)
    first = saboteur(dir, *scoped_args, "--shard", "1/2")
    second = saboteur(dir, *scoped_args, "--shard", "2/2")

    full_ids = mutants(full).map { |m| m["id"] }
    first_ids = mutants(first).map { |m| m["id"] }
    second_ids = mutants(second).map { |m| m["id"] }
    expect(first_ids).not_to be_empty
    expect(second_ids).not_to be_empty
    expect(first_ids & second_ids).to be_empty
    expect((first_ids + second_ids).sort).to eq(full_ids.sort)
  end

  it "is deterministic: the same shard selects the same mutants again" do
    first = saboteur(dir, *scoped_args, "--shard", "1/2")
    again = saboteur(dir, *scoped_args, "--shard", "1/2")

    expect(mutants(again).map { |m| m["id"] }).to eq(mutants(first).map { |m| m["id"] })
    expect(again.out).to include("partial run")
  end
end
