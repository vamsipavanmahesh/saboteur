# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Locks review issue #128: with --incremental, a survivor from an earlier run
# must be judged again once a new spec exists that can kill it.
RSpec.describe "--incremental cache invalidation by a new spec (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }
  let(:subject_flags) { ["--incremental", "--subject", "People::Person#adult?"] }

  def boundary_mutants(run)
    mutants(run).select { |m| m["mutatorName"] == "comparison" }
  end

  it "re-runs a surviving mutant and kills it after a new spec file covers the boundary" do
    first = saboteur(dir, *subject_flags)
    survivors = boundary_mutants(first).select { |m| m["status"] == "Survived" }
    expect(survivors).not_to be_empty

    File.write(File.join(dir, "spec", "boundary_edge_spec.rb"), <<~RUBY)
      require_relative "../lib/people"

      RSpec.describe People::Person do
        it "is an adult at exactly 18" do
          expect(described_class.new(18).adult?).to be(true)
        end
      end
    RUBY

    second = saboteur(dir, *subject_flags)
    now = boundary_mutants(second).select { |m| survivors.map { |s| s["id"] }.include?(m["id"]) }
    expect(now.map { |m| m["status"] }).to include("Killed")
    expect(second.out).not_to include("reused #{mutants(second).size} of #{mutants(second).size}")
    expect(second.json.fetch("testFiles").keys.join).to include("boundary_edge_spec.rb")
  end
end
