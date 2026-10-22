# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# README ("Survivors you can act on"): "Survivors group per statement with a
# triage label (likely_equivalent, arid, tool_limit, or a gap kind) and
# their covering tests." The triage fixture leaves survivors on a logging
# line, a comparison, a ternary and a default value. likely_equivalent and
# tool_limit need an equivalent mutant and an external runner, and have
# their own specs.
RSpec.describe "survivor triage labels per statement (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("triage"), "--all") }

  def survivors_on(line)
    mutants(run).select { |m| m["status"] == "Survived" && m.dig("location", "start", "line") == line }
  end

  def line_of(text)
    File.readlines(File.join(run.dir, "lib", "demo.rb")).index { |source| source.include?(text) } + 1
  end

  it "labels every survivor of a statement by what its edit would have needed" do
    expect(run.status).to eq(1), run.err
    labels = lambda do |text|
      survivors_on(line_of(text)).to_h { |m| [m["mutatorName"], m["classification"]] }
    end

    expect(labels.call("puts")).to eq("statement_removal" => "arid", "interpolation_removal" => "arid")
    expect(labels.call("count >= 10")).to eq("comparison" => "boundary", "literal_number" => "number")
    expect(labels.call("flag ?")).to eq("condition_true" => "branch", "condition_false" => "branch",
                                        "condition_negation" => "branch")
    expect(labels.call("hash[:name]")).to eq("boolean_logic" => "branch", "literal_string" => "result unchecked")
  end

  it "prints one block per statement with its triage label, id and the mutants folded under it" do
    expect(run.out).to include("lib/demo.rb:#{line_of('puts')} Demo#noisy [arid] - ")
    expect(run.out).to include("lib/demo.rb:#{line_of('count >= 10')} Demo#limit [boundary] - ")
    expect(run.out).to include("lib/demo.rb:#{line_of('flag ?')} Demo#pick [branch] - ")
    # One label per statement from all its mutants (#P4): fetch_name holds a
    # branch and a result unchecked mutant, and result unchecked outranks it.
    expect(run.out).to include("lib/demo.rb:#{line_of('hash[:name]')} Demo#fetch_name [result unchecked] - ")
    expect(run.out).to include("Survivors (11) - changes your tests did not catch")
    expect(run.out).to include("#1 of 4 blocks", "#2 of 4 blocks")
    expect(run.out).to include("every edited line matches an arid pattern")
    expect(run.out).to include("2 more mutants here:")
  end

  it "names the covering test of each statement and that it ran and still passed" do
    expect(run.out).to include("covered by ./spec/demo_spec.rb[1:1] - ran, still passed")
    expect(run.out).to include("covered by ./spec/demo_spec.rb[1:2] - ran, still passed")
    covered = survivors_on(line_of("count >= 10")).flat_map { |m| m["coveredBy"] }.uniq
    expect(test_names(run, covered)).to eq(["./spec/demo_spec.rb[1:2]"])
  end
end
