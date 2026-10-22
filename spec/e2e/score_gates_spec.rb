# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# README ("Built for big suites"): "per-path score gates hold one subtree to
# a stricter floor." The people fixture scores 89.3% on lib/people.rb and
# 61.5% on lib/stage.rb, so a floor between those two numbers separates them.
RSpec.describe "saboteur run with score gates (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  def gate_config(*gates)
    lines = gates.map { |pattern, floor| %(  c.score_gate "#{pattern}", min_score: #{floor}) }
    File.write(File.join(dir, "config", "saboteur.rb"), <<~RUBY)
      Saboteur.configure do |c|
        c.include = ["lib/**/*.rb"]
      #{lines.join("\n")}
      end
    RUBY
  end

  # --threshold 0 stops plain survivors from failing the run, so the exit
  # code isolates what the score gates decided.
  def run_gated
    saboteur(dir, "lib/people.rb", "lib/stage.rb", "--threshold", "0")
  end

  def breakdown(run, pattern)
    run.json.fetch("saboteur").fetch("scoreGates").find { |gate| gate["pattern"] == pattern }
  end

  it "passes silently when every subtree is above its own floor" do
    gate_config(["lib/people.rb", 85], ["lib/stage.rb", 50])
    run = run_gated

    expect(run.status).to eq(0), other_outcomes(run)
    expect(run.err).not_to include("score gate")
    expect(breakdown(run, "lib/people.rb")).to include("passed" => true, "score" => 89.3)
    expect(breakdown(run, "lib/stage.rb")).to include("passed" => true, "score" => 61.5)
  end

  it "fails the run on the one subtree under its floor and names it" do
    gate_config(["lib/people.rb", 85], ["lib/stage.rb", 100])
    run = run_gated

    expect(run.status).to eq(1), other_outcomes(run)
    expect(run.err).to include("score gate lib/stage.rb: score 61.5 below 100.0")
    expect(run.err).to include("1 failing subject(s), 1 matched file(s): lib/stage.rb")
    expect(run.err).not_to include("score gate lib/people.rb")
    expect(breakdown(run, "lib/stage.rb")).to include("passed" => false, "failingSubjects" => 1)
    expect(breakdown(run, "lib/people.rb")).to include("passed" => true)
  end

  it "scores each mutant under its most specific gate only" do
    gate_config(["lib/*.rb", 100], ["lib/people.rb", 85])
    run = run_gated

    expect(breakdown(run, "lib/people.rb")).to include("mutants" => 28, "files" => ["lib/people.rb"])
    expect(breakdown(run, "lib/*.rb")).to include("files" => ["lib/stage.rb"], "passed" => false)
    expect(run.err).to include("score gate lib/*.rb: 6 subject(s) also match a more specific gate and score there")
    expect(run.status).to eq(1)
  end
end
