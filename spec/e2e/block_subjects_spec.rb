# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Methods defined inside blocks are named as skipped subjects, covered or not,
# and never turn into mutants or survivors (#114).
RSpec.describe "block-defined subjects (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("blocks")) }

  it "mutates the plain class and finishes cleanly" do
    expect(run.status).to eq(0), other_outcomes(run)
    expect(mutants(run).map { |m| m["status"] }.uniq).to eq(["Killed"])
  end

  it "names covered, uncovered and empty block methods as defined inside a block" do
    %w[Covered#doubled Uncovered#tripled Uncovered#nothing].each do |id|
      expect(run.out).to include("#{id} lib/blocks.rb:").and include("defined inside a block")
    end
    expect(run.out).not_to include("no coverage")
  end

  it "does not treat a non-factory block as a class owner" do
    expect(run.out).to include("(anonymous block)#registered").or include("Plain#registered")
    expect(run.out).not_to include("Registry#registered")
  end

  it "generates no mutants inside block-defined methods" do
    lines = mutants(run).map { |m| m.dig("location", "start", "line") }
    expect(lines.all? { |line| line < 9 }).to be(true)
  end
end
