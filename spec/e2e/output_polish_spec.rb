# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Small output fixes (P6): the run header names a --subject scope, an
# untested subject is named once, and the replay example is the #1 survivor.
RSpec.describe "run output polish", :e2e do
  let(:dir) do
    copy_fixture("people").tap do |copy|
      File.open(File.join(copy, "lib", "people.rb"), "a") do |file|
        file.puts "class Untested\n  def value\n    123\n  end\nend"
      end
    end
  end
  let(:run) { saboteur(dir, "--all", "--subject", "Untested", "--subject", "People::Person#adult?") }

  it "names the --subject scope in the run header, not whole project" do
    expect(run.err).to include("--subject Untested, People::Person#adult?")
    expect(run.err).not_to include("whole project")
  end

  it "names an untested subject once, in the Not scored block, and counts it elsewhere" do
    full = saboteur(dir, "--all")
    expect(full.out).to include("Score by file", "Not scored - no test executes these")
    expect(full.out.scan("Untested#value").size).to eq(1)
    expect(full.out).to include("1 subject not scored - no test executes it", "1 subject untested")
  end

  it "replays the top-ranked survivor, the one listed first in the report" do
    expect(run.status).to eq(1), run.err
    top = run.json.dig("saboteur", "findings", "survivors", 0, "digest")
    expect(run.out).to include("replay one survivor: saboteur run --id #{top}")
  end
end
