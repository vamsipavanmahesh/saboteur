# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "--fail-fast (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  it "records the subjects it never ran and cannot pass a threshold" do
    run = saboteur(dir, "--fail-fast", "--threshold", "0")
    expect(run.status).to eq(1), run.err
    stop = run.json.fetch("earlyStop")
    expect(stop.fetch("reason")).to eq("fail_fast")
    expect(stop.fetch("unreachedSubjects")).to include("Stage.for")
    expect(run.json.fetch("saboteur").fetch("exitCause")).to eq("failFast")
    expect(run.out).to include("stopped early (--fail-fast):", "not run: Stage.for")
  end

  it "marks the agent summary partial, keeping the survivors verdict" do
    run = saboteur(dir, "--fail-fast", "--agent")
    payload = JSON.parse(run.out)
    expect(payload).to include("status" => "partial", "verdict" => "survivors")
    expect(payload.fetch("incomplete")).to include(a_hash_including("reason" => "fail_fast"))
    expect(run.json.fetch("earlyStop").fetch("unreachedSubjects")).not_to be_empty
  end

  it "leaves earlyStop null for a run that covered its whole selection" do
    run = saboteur(dir)
    expect(run.json.fetch("earlyStop")).to be_nil
  end

  it "keeps going past a subject whose survivors the ignore list accepts" do
    first = saboteur(dir, "--fail-fast")
    ignored = first.json.dig("saboteur", "findings", "survivors").select { |s| s["subject"] == "People::Person#adult?" }
    entries = ignored.map { |s| %(  i.mutation "#{s['digest']}", subject: "#{s['subject']}", reason: "accepted") }
    File.write(File.join(dir, "config", "saboteur_ignore.rb"), "Saboteur.ignore do |i|\n#{entries.join("\n")}\nend\n")
    second = saboteur(dir, "--fail-fast")
    before = first.json.dig("earlyStop", "unreachedSubjects")
    after = second.json.dig("earlyStop", "unreachedSubjects") || []
    expect(after.size).to be < before.size
  end

  it "refuses to combine with more than one job" do
    run = saboteur(dir, "--fail-fast", "--jobs", "2")
    expect(run.status).to eq(2)
    expect(run.err).to include("fail_fast needs jobs 1")
  end
end
