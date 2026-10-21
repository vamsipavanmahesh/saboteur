# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Locks review issue #128: with --incremental, a survivor from an earlier run
# must be judged again once a new spec exists that can kill it, and verdicts
# are still reused when nothing changed.
RSpec.describe "--incremental cache invalidation by a new spec (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }
  let(:subject_flags) { ["--incremental", "--subject", "People::Person#adult?"] }
  let(:boundary_spec) { File.join(dir, "spec", "boundary_edge_spec.rb") }

  def ids_with_status(run, status)
    mutants(run).select { |m| m["status"] == status }.map { |m| m["id"] }.sort
  end

  def test_ids_in(run, file)
    run.json.fetch("testFiles").fetch(file).fetch("tests").map { |test| test.fetch("id") }
  end

  def write_boundary_spec
    File.write(boundary_spec, <<~RUBY)
      require_relative "../lib/people"

      RSpec.describe People::Person do
        it "is an adult at exactly 18" do
          expect(described_class.new(18).adult?).to be(true)
        end
      end
    RUBY
  end

  it "judges every earlier survivor again and kills each one with the new spec" do
    first = saboteur(dir, "--all", *subject_flags)
    prior_survivors = ids_with_status(first, "Survived")
    expect(prior_survivors).not_to be_empty

    write_boundary_spec
    second = saboteur(dir, "--all", *subject_flags)
    new_test_ids = test_ids_in(second, "spec/boundary_edge_spec.rb")
    expect(new_test_ids.size).to eq(1)

    again = mutants(second).select { |m| prior_survivors.include?(m["id"]) }
    expect(again.map { |m| m["id"] }.sort).to eq(prior_survivors)
    expect(again.map { |m| m["status"] }.uniq).to eq(["Killed"])
    expect(again.map { |m| m["killedBy"] }).to all(eq(new_test_ids))
    expect(ids_with_status(second, "Survived")).to be_empty
  end

  it "does not reuse any verdict once the new spec changes what covers the method" do
    saboteur(dir, "--all", *subject_flags)
    write_boundary_spec
    second = saboteur(dir, "--all", *subject_flags)

    expect(second.out).to include("no verdicts reused from earlier runs (--incremental)")
    expect(second.out).not_to match(/reused [1-9]/)
    # A fresh verdict records the tests that ran against the mutant.
    expect(mutants(second).map { |m| m["executed"] }).to all(be_a(Array))
  end

  it "reuses every verdict when nothing changed (positive control)" do
    first = saboteur(dir, "--all", *subject_flags)
    write_boundary_spec
    second = saboteur(dir, "--all", *subject_flags)
    third = saboteur(dir, "--all", *subject_flags)
    total = mutants(third).size

    expect(first.out).to include("no verdicts reused from earlier runs (--incremental)")
    # A reused verdict keeps its killer but has no executed-tests record.
    expect(third.out).to include("#{total}/#{total} mutants killed")
    expect(mutants(third).map { |m| m["executed"] }.uniq).to eq([nil])
    expect(mutants(third).map { |m| [m["id"], m["status"]] }).to eq(mutants(second).map { |m| [m["id"], m["status"]] })
  end
end
