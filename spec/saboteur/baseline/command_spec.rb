# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"
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
    expect(workflow).to receive(:check).with(path: "b.json", epsilon: nil)
                                       .and_return("state" => "review_required", "exit_code" => 1,
                                                   "categories" => {}, "issues" => [])
    expect(command("check", "--baseline", "b.json")).to eq(1)
    expect(JSON.parse(@out.string)["state"]).to eq("review_required")
  end

  it "passes --epsilon to check and rejects it elsewhere or out of range" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    expect(workflow).to receive(:check).with(path: "b.json", epsilon: 2.5)
                                       .and_return("state" => "clean", "exit_code" => 0, "categories" => {},
                                                   "issues" => [])
    expect(command("check", "--baseline", "b.json", "--epsilon", "2.5")).to eq(0)
    expect(command("propose", "--baseline", "b.json", "--proposal", "p.json", "--epsilon", "1")).to eq(2)
    expect(@err.string).to include("--epsilon applies to check only")
    expect(command("check", "--baseline", "b.json", "--epsilon", "-1")).to eq(2)
    expect(@err.string).to include("--epsilon must be between 0 and 100")
    expect(command("check", "--baseline", "b.json", "--epsilon", "100.5")).to eq(2)
    expect(@err.string).to include("--epsilon must be between 0 and 100")
  end

  it "accepts the epsilon bounds 0 and 100 and values between them" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    allow(workflow).to receive(:check).and_return("state" => "clean", "exit_code" => 0, "categories" => {},
                                                  "issues" => [])
    %w[0 0.5 100].each do |value|
      expect(command("check", "--baseline", "b.json", "--epsilon", value)).to eq(0), value
    end
  end

  it "passes explicit proposal destinations and reviewed hashes to acceptance" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    expect(workflow).to receive(:accept).with(proposal: "p.json", destination: "b.json", previous: "a" * 64)
                                        .and_return("state" => "accepted", "destination" => "b.json")
    expect(command("accept", "--baseline", "b.json", "--proposal", "p.json", "--previous", "a" * 64)).to eq(0)
  end

  it "parses subjects, seeds and config locations and executes a proposal with exact fields" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    expect(Saboteur::Baseline::Workflow).to receive(:new) do |config:, err:|
      expect(config["subjects"]).to eq(["A#m", "B.n"])
      expect(config["seed"]).to eq(7)
      expect(err).to eq(@err)
      workflow
    end
    expect(workflow).to receive(:propose).with(proposal: "p.json", destination: "b.json", previous: "a" * 64)
                                         .and_return("state" => "proposal")
    config_path = File.join(Dir.mktmpdir, "custom.rb")
    File.write(config_path, "")
    expect(command("propose", "--config", config_path, "--baseline", "b.json", "--proposal", "p.json",
                   "--subject", "A#m", "--subject", "B.n", "--seed", "7", "--previous", "a" * 64,
                   "--format", "json")).to eq(0)
    expect(JSON.parse(@out.string)).to eq("state" => "proposal")
  end

  it "does not treat a proposal as optional for acceptance or a previous hash as valid for check" do
    expect(command("accept", "--baseline", "b.json")).to eq(2)
    expect(@err.string).to include("--proposal PATH is required")
    expect(command("check", "--baseline", "b.json", "--previous", "a" * 64)).to eq(2)
    expect(@err.string).to include("check does not use")
    expect(command("check")).to eq(2)
    expect(@err.string).to include("--baseline PATH is required (for example: saboteur baseline check " \
                                   "--baseline baseline.json)")
    expect(command("bad")).to eq(2)
    expect(@err.string).to include("baseline expects")
    expect(command("propose", "--baseline", "b.json", "--proposal", "p.json", "--previous", "0" * 63)).to eq(2)
    expect(@err.string).to include("--previous needs a SHA-256")
    expect(command("check", "--baseline", "b.json", "other", "more")).to eq(2)
    expect(@err.string).to include("unexpected arguments: other more")
  end

  it "pins the public option descriptions and usage banner" do
    parser = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new).baseline_parser
    expect(parser.banner).to eq("Usage: saboteur baseline check|propose|accept --baseline PATH [--proposal PATH] " \
                                "[--epsilon POINTS]")
    text = parser.summarize.join
    ["Accepted baseline destination", "Editable proposal path (propose/accept)",
     "Reviewed current destination hash for replacement", "Config file (default config/saboteur.rb)",
     "Whole subject filter; repeatable", "Repeatable run seed",
     "check: also fail when the score drops more than POINTS"].each do |description|
      expect(text).to include(description)
    end
  end

  it "rejects a fractional seed rather than silently coercing it to an integer" do
    expect(command("check", "--baseline", "b.json", "--seed", "1.5")).to eq(2)
    expect(@err.string).to include("invalid argument")
  end

  it "shows help and distinguishes rejected acceptance from tool failure" do
    expect(command("--help")).to eq(0)
    expect(@out.string).to include("propose", "--previous")
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_raise(Saboteur::ConfigError, "invalid")
    expect(command("check", "--baseline", "b.json")).to eq(2)
    expect(@err.string).to include("saboteur: invalid")
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_raise(Saboteur::Error, "stopped")
    expect(command("check", "--baseline", "b.json")).to eq(3)
    expect(@err.string).to include("saboteur: stopped")
  end

  it "prints the proposal in terminal form by default, listing soft gaps" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    allow(workflow).to receive(:propose).and_return(
      "state" => "proposal", "proposal" => "/tmp/p.json", "destination" => "/tmp/b.json",
      "survivors" => 1, "candidates" => 3, "gaps" => ["subject_skipped:probe.rb:Probe#other:no_tests"]
    )
    expect(command("propose", "--baseline", "b.json", "--proposal", "p.json")).to eq(0)
    expected = <<~TEXT
      baseline proposal written: /tmp/p.json
        matched mutants: 3 (1 survivor to reason about)
        proposed with 1 untested subject: probe.rb:Probe#other:no_tests - the baseline cannot speak for them
    TEXT
    expected += "  next step: give each accepted survivor a reason in the proposal, then run: " \
                "saboteur baseline accept --baseline /tmp/b.json --proposal /tmp/p.json\n"
    expect(@out.string).to eq(expected)
  end

  it "prints a gap-free proposal without the untested-subjects line" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    allow(workflow).to receive(:propose).and_return(
      "state" => "proposal", "proposal" => "/tmp/p.json", "destination" => "/tmp/b.json",
      "survivors" => 1, "candidates" => 3
    )
    expect(command("propose", "--baseline", "b.json", "--proposal", "p.json")).to eq(0)
    expected = <<~TEXT
      baseline proposal written: /tmp/p.json
        matched mutants: 3 (1 survivor to reason about)
    TEXT
    expected += "  next step: give each accepted survivor a reason in the proposal, then run: " \
                "saboteur baseline accept --baseline /tmp/b.json --proposal /tmp/p.json\n"
    expect(@out.string).to eq(expected)
  end

  it "repeats the propose scope flags in the next-step accept command" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    allow(workflow).to receive(:propose).and_return(
      "state" => "proposal", "proposal" => "/tmp/p.json", "destination" => "/tmp/b.json",
      "survivors" => 2, "candidates" => 3
    )
    Dir.mktmpdir do |dir|
      config = File.join(dir, "saboteur.rb")
      File.write(config, "")
      expect(command("propose", "--subject", "People::Person", "--seed", "7", "--config", config,
                     "--baseline", "b.json", "--proposal", "p.json")).to eq(0)
      expect(@out.string).to include("2 survivors to reason about")
      expect(@out.string).to include("saboteur baseline accept --subject People::Person --seed 7 " \
                                     "--config #{config} --baseline /tmp/b.json --proposal /tmp/p.json")
    end
  end

  it "joins several gaps with a comma and strips only a leading gap prefix" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    allow(workflow).to receive(:propose).and_return(
      "state" => "proposal", "proposal" => "/tmp/p.json", "destination" => "/tmp/b.json",
      "survivors" => 0, "candidates" => 3,
      "gaps" => ["subject_skipped:probe.rb:Probe#other:no coverage", "note:subject_skipped:inner"]
    )
    expect(command("propose", "--baseline", "b.json", "--proposal", "p.json")).to eq(0)
    expect(@out.string).to include(
      "  proposed with 2 untested subjects: probe.rb:Probe#other:no coverage, " \
      "note:subject_skipped:inner - the baseline cannot speak for them"
    )
  end

  it "accepts --format terminal explicitly" do
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    allow(workflow).to receive(:propose).and_return(
      "state" => "proposal", "proposal" => "/tmp/p.json", "destination" => "/tmp/b.json",
      "survivors" => 1, "candidates" => 3
    )
    expect(command("propose", "--baseline", "b.json", "--proposal", "p.json", "--format", "terminal")).to eq(0)
    expect(@out.string).to start_with("baseline proposal written:")
  end

  it "rejects a bad or misplaced --format and pins the refusal exit code at 3" do
    expect(command("propose", "--baseline", "b.json", "--proposal", "p.json", "--format", "yaml")).to eq(2)
    expect(command("check", "--baseline", "b.json", "--format", "json")).to eq(2)
    workflow = instance_double(Saboteur::Baseline::Workflow)
    allow(Saboteur::Baseline::Workflow).to receive(:new).and_return(workflow)
    allow(workflow).to receive(:propose)
      .and_raise(Saboteur::Error, "baseline proposal needs a proposable run")
    expect(command("propose", "--baseline", "b.json", "--proposal", "p.json")).to eq(3)
    expect(@err.string).to include("saboteur: baseline proposal needs a proposable run")
  end
end
