# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"

RSpec.describe Saboteur::CLI, "agent mode" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    described_class.new(argv, out:, err:)
  end

  def run_agent(report, *flags)
    engine = instance_double(Saboteur::Engine, call: report)
    allow(Saboteur::Engine).to receive(:new).and_return(engine)
    Dir.mktmpdir do |dir|
      code = cli("run", *flags, "--json", File.join(dir, "r.json"), "--html", File.join(dir, "r.html")).call
      [code, JSON.parse(out.string, symbolize_names: true)]
    end
  end

  {
    "clean" => [[:killed], 0, "clean"],
    "survivor" => [[:survived], 1, "survivors"],
    "killed and errored" => [%i[killed error], 3, "incomplete"]
  }.each do |name, (statuses, code, verdict)|
    it "exits #{code} with verdict #{verdict} for a #{name} run" do
      results = statuses.each_with_index.map { |status, index| result_for(status, replacement: "r#{index}") }
      exit_code, payload = run_agent(report_of(*results), "--agent")
      expect([exit_code, payload[:verdict], payload[:exitCode]]).to eq([code, verdict, code])
    end
  end

  it "prints only the JSON payload on stdout, and still writes the report files" do
    Dir.mktmpdir do |dir|
      json = File.join(dir, "r.json")
      engine = instance_double(Saboteur::Engine, call: report_of(result_for(:killed)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      cli("run", "--format", "agent", "--json", json).call
      expect(JSON.parse(out.string)["status"]).to eq("complete")
      expect(File.exist?(json)).to be(true)
    end
  end

  it "keeps the classic exit code for a mixed run without --agent" do
    engine = instance_double(Saboteur::Engine, call: report_of(result_for(:killed), result_for(:error,
                                                                                               replacement: "<")))
    allow(Saboteur::Engine).to receive(:new).and_return(engine)
    expect(cli("run", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
    expect(out.string).to include("score 100.0 %")
  end

  it "answers a config error with a JSON payload and exit 2" do
    allow(Saboteur::Engine).to receive(:new)
    expect(cli("run", "--agent", "--jobs", "0").call).to eq(2)
    expect(JSON.parse(out.string)).to include("status" => "error", "verdict" => "invalid_invocation", "exitCode" => 2)
  end

  it "answers a tool failure with a JSON payload and exit 3" do
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "boot failed")
    expect(cli("run", "--agent").call).to eq(3)
    expect(JSON.parse(out.string)).to include("verdict" => "tool_failure", "message" => "boot failed")
  end

  it "refuses --threshold together with --agent, because exit 0 would mean two things" do
    allow(Saboteur::Engine).to receive(:new)
    expect(cli("run", "--agent", "--threshold", "90").call).to eq(2)
    expect(JSON.parse(out.string)).to include("verdict" => "invalid_invocation")
    expect(err.string).to include("--threshold cannot be combined with --agent")
    expect(Saboteur::Engine).not_to have_received(:new)
  end

  it "rejects an unknown format with exit 2" do
    expect(cli("run", "--format", "xml").call).to eq(2)
  end

  describe "saboteur agent-skill" do
    it "prints the instructions block" do
      expect(cli("agent-skill").call).to eq(0)
      expect(out.string).to eq(Saboteur::AgentSkill::TEXT)
    end

    it "matches the copy in docs/agent-skill.md" do
      docs = File.read(File.expand_path("../../docs/agent-skill.md", __dir__))
      expect(docs).to include(Saboteur::AgentSkill::TEXT)
    end

    it "names only commands and flags that exist" do
      options = cli.parser.top.list.flat_map(&:long)
      expect(options).to include("--agent", "--since")
      expect(Saboteur::AgentSkill::TEXT).to include("saboteur run --agent --since origin/main", "next.replay")
    end
  end
end
