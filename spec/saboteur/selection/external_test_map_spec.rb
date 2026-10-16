# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The external mode's coverage map: every mutant maps to the same pseudo
# test, whatever shape the question takes (#140, #305).
RSpec.describe Saboteur::Selection::ExternalTestMap do
  subject(:map) { described_class.new }

  it "answers the pseudo test for subjects, edits and branches alike" do
    expect(map.tests_for(:subject)).to eq(["(test command)"])
    expect(map.tests_for_edit(:subject, [1])).to eq(["(test command)"])
    expect(map.tests_for_branches(:subject, [:edit])).to eq(["(test command)"])
  end

  it "never marks a file as ran at load and records no runtime" do
    expect(map.ran_at_load?("a.rb", [1])).to be(false)
    expect(map.recorded_runtime(["(test command)"])).to be_nil
  end
end
