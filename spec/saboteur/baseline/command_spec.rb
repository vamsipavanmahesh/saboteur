# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "saboteur/cli"

RSpec.describe "baseline CLI validation" do
  def command(*args)
    @out = StringIO.new
    @err = StringIO.new
    Saboteur::CLI.new(["baseline", *args], out: @out, err: @err).call
  end

  it "rejects unknown actions, absent paths, unrelated flags and malformed replacement hashes before execution" do
    allow(Saboteur::Baseline::Workflow).to receive(:new)
    [[], ["bad"], ["check"], ["propose", "--baseline", "b.json"],
     ["accept", "--baseline", "b.json", "--proposal", "p.json", "--previous", "bad"],
     ["check", "--baseline", "b.json", "--proposal", "p.json"],
     ["check", "--baseline", "b.json", "--since", "main"],
     ["check", "--baseline", "b.json", "unexpected"]].each do |args|
      expect(command(*args)).to eq(2), args.inspect
    end
    expect(Saboteur::Baseline::Workflow).not_to have_received(:new)
  end

  it "renders strict JSON and preserves check state exit codes" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    expect(workflow).to receive(:check).with(path: "b.json")
                                       .and_return("state" => "review_required", "exit_code" => 1,
                                                   "categories" => {}, "issues" => [])
    expect(command("check", "--baseline", "b.json")).to eq(1)
    expect(JSON.parse(@out.string)["state"]).to eq("review_required")
  end

  it "passes explicit proposal destinations and reviewed hashes to acceptance" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    expect(workflow).to receive(:accept).with(proposal: "p.json", destination: "b.json", previous: "a" * 64)
                                        .and_return("state" => "accepted", "destination" => "b.json")
    expect(command("accept", "--baseline", "b.json", "--proposal", "p.json", "--previous", "a" * 64)).to eq(0)
  end

  it "shows help and distinguishes rejected acceptance from tool failure" do
    expect(command("--help")).to eq(0)
    expect(@out.string).to include("propose", "--previous")
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_raise(Saboteur::ConfigError, "invalid")
    expect(command("check", "--baseline", "b.json")).to eq(2)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_raise(Saboteur::Error, "stopped")
    expect(command("check", "--baseline", "b.json")).to eq(3)
  end
end
