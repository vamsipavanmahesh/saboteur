# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "endless defs (end to end)", :e2e do
  it "tests endless defs through method coverage instead of skipping them" do
    dir = copy_fixture("endless")
    run = saboteur(dir)
    expect(run.status).to be <= 1, other_outcomes(run)
    expect(run.json.fetch("skippedSubjects")).to be_empty
    statuses = mutants(run).map { |m| m["status"] }.uniq
    expect(statuses).to include("Killed")
    expect(statuses - %w[Killed Survived]).to be_empty
  end

  it "names the real cause when a whole-suite build records nothing at all" do
    dir = copy_fixture("endless")
    File.write(File.join(dir, "spec", "endless_math_spec.rb"), <<~RUBY)
      RSpec.describe "unrelated" do
        it("adds") { expect(1 + 1).to eq(2) }
      end
    RUBY
    run = saboteur(dir)
    expect(run.status).to eq(3)
    expect(run.err).to include("Coverage recorded nothing in 1 included files",
                               "No test in the suite may exercise these files")
  end
end
