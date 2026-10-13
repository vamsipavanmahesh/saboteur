# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Locks review issue #122: when the only test of a method lives in a consumer's
# spec, the mutant is still killed through that spec.
RSpec.describe "cross-class test selection (end to end)", :e2e do
  source = File.join(E2EHelpers::ROOT, "spec/fixtures/projects/crossclass/lib/pieces.rb")
  lines = File.readlines(source)
  # [description, a line of the method under test, the consumer's describe group, by position in the spec]
  cases = [
    ["a transitive dependency (Leaf, tested only through Top)", "10 + 5", 1],
    ["an inherited method that calls super", 'super + " world"', 2],
    ["a mixin method", "text.upcase", 3],
    ["a prepended module", '"<" + super', 4],
    ["a Forwardable delegate target", "40 + 2", 5],
    ["method_missing", "helper(name) if", 6],
    ["Comparable via <=>", "number <=> other.number", 7],
    ["a block run in Thread.new", "Thread.new { 6 * 7 }", 8],
    ["a value computed in before(:all)", "100 + 1", 9],
    ["an instance_eval DSL method", "number * 2", 10],
    ["a late-bound lambda target", "number + 1000", 11]
  ]

  before(:context) do
    @run = saboteur(copy_fixture("crossclass"))
  end

  it "kills every mutant and leaves no survivors" do
    expect(@run.status).to eq(0), other_outcomes(@run)
    expect(mutants(@run).map { |m| m["status"] }.uniq).to eq(["Killed"])
  end

  cases.each do |description, text, group|
    it "kills a mutant in #{description} through the consumer's spec" do
      line = lines.index { |candidate| candidate.include?(text) } + 1
      on_line = mutants(@run).select { |m| m.dig("location", "start", "line") == line }
      expect(on_line).not_to be_empty
      expect(on_line.map { |m| m["status"] }.uniq).to eq(["Killed"])
      killers = test_names(@run, on_line.flat_map { |m| m["killedBy"].to_a }.uniq)
      expect(killers).to all(match(/pieces_spec\.rb\[#{group}:/))
    end
  end
end
