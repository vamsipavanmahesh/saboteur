# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Methods defined inside blocks are named, covered or not (#114). Defs in the
# four core class factories (`X = Data.define`, `Struct.new`, ...) belong to
# the named class: they re-evaluate through X.class_eval and are ordinary
# subjects (#290). Defs in any other block stay skipped as
# "defined inside a block".
RSpec.describe "block-defined subjects (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("blocks")) }

  it "mutates the plain class and finishes cleanly" do
    expect(run.status).to eq(0), other_outcomes(run)
    expect(mutants(run).map { |m| m["status"] }.uniq).to eq(["Killed"])
  end

  it "names uncovered factory methods as no coverage, not skipped (#290)" do
    expect(run.out).to include("2 subjects not scored - no test executes these methods: " \
                               "Uncovered#tripled, Uncovered#nothing")
    expect(run.out).not_to include("Covered#doubled")
  end

  it "does not treat a non-factory block as a class owner" do
    verbose_run = saboteur(copy_fixture("blocks"), "--verbose")
    expect(verbose_run.out).to include("(anonymous block)#registered").or include("Plain#registered")
    expect(verbose_run.out).not_to include("Registry#registered")
  end

  it "mutates the factory-defined methods and no other block-defined ones" do
    # Line 5 is Plain#succ, line 11 Covered#doubled: the uncovered Struct
    # methods and the non-factory Registry block still generate nothing.
    lines = mutants(run).map { |m| m.dig("location", "start", "line") }
    expect(lines.uniq.sort).to eq([5, 11])
  end
end
