# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# #353: a helper required lazily inside a test (outside the include list, so
# the recorder drops it and the parent process never loads it) must still
# invalidate cached verdicts when it changes.
RSpec.describe "--incremental cache invalidation for a lazy dependency (end to end)", :e2e do
  let(:dir) { copy_fixture("lazy_dep") }
  let(:helper) { File.join(dir, "support", "helper.rb") }
  let(:flags) { ["--incremental", "--subject", "Person#check"] }

  it "re-runs every verdict when a source only the coverage child loaded changes" do
    first = saboteur(dir, "--all", *flags)
    expect(mutants(first).map { |m| m["status"] }).to include("Killed")

    File.write(helper, "module Helper\n  def self.value = 10\nend\n")
    second = saboteur(dir, "--all", *flags)

    expect(second.out).not_to match(/reused \d+ of \d+ verdicts/)
    prior = mutants(first).to_h { |m| [m["id"], m["status"]] }
    now = mutants(second).to_h { |m| [m["id"], m["status"]] }
    flipped = prior.count { |id, status| status == "Survived" && now[id] == "Killed" }
    expect(flipped).to be_positive
  end

  it "still reuses every verdict when nothing changed (positive control)" do
    saboteur(dir, "--all", *flags)
    second = saboteur(dir, "--all", *flags)
    total = mutants(second).size

    expect(second.out).to include("reused #{total} of #{total} verdicts")
  end
end
