# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# A file nested deeper than the recursive AST walkers survive must refuse
# the run cleanly: one line naming the file, exit 3 - never a raw
# SystemStackError (#719).
RSpec.describe "deeply nested source (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("deep_nesting")) }

  it "refuses the run with exit 3 and names the file" do
    expect(run.status).to eq(3)
    expect(run.err).to include("lib/deep.rb").and include("nests deeper")
    expect(run.err).not_to include("SystemStackError")
  end
end
