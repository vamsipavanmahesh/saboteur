# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

# README ("Reports for people and tools"): "saboteur badge and saboteur
# trend track the score history with no hosted service."
RSpec.describe "score history with badge and trend (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  def configure_history
    File.write(File.join(dir, "config", "saboteur.rb"), <<~RUBY)
      Saboteur.configure do |c|
        c.include = ["lib/**/*.rb"]
        c.score_history = ".saboteur/history.jsonl"
      end
    RUBY
  end

  def scoped_run
    saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb")
  end

  it "records one JSONL record per run, and badge prints it as a shields.io endpoint" do
    configure_history
    scoped_run

    records = File.readlines(File.join(dir, ".saboteur", "history.jsonl")).map { |line| JSON.parse(line) }
    expect(records.size).to eq(1)
    expect(records.first["score"]).to be_between(0.0, 1.0)

    badge = saboteur(dir, command: "badge")
    expect(badge.status).to eq(0)
    endpoint = JSON.parse(badge.out)
    expect(endpoint["schemaVersion"]).to eq(1)
    expect(endpoint["label"]).to eq("mutation score")
    expect(endpoint["message"]).to match(/\A\d+(\.\d+)?%\z/)
    expect(endpoint["color"]).to eq("brightgreen")

    out_file = File.join(dir, "badge.json")
    written = saboteur(dir, "--output", out_file, command: "badge")
    expect(written.status).to eq(0)
    expect(JSON.parse(File.read(out_file))).to eq(endpoint)
  end

  it "trend says when no record compares, then prints the delta after a second run" do
    configure_history
    scoped_run
    first = saboteur(dir, command: "trend")
    expect(first.status).to eq(0)
    expect(first.out).to include("no comparable earlier record")

    scoped_run
    second = saboteur(dir, command: "trend")
    expect(second.status).to eq(0)
    expect(second.out).to include("covered score change +0.00 percentage points")
  end
end
