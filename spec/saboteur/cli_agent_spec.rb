# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"
require "open3"
require "rbconfig"
require "fileutils"
require "tmpdir"
require_relative "../support/e2e_helpers"

RSpec.describe Saboteur::CLI, "agent mode" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    described_class.new(argv, out:, err:)
  end

  def run_agent(report, *flags)
    engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
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

  it "carries only setting flags plus the operator lists in agent settings" do
    _code, payload = run_agent(report_of(result_for(:killed)), "--agent", "--operators", "range")
    settings = payload[:provenance][:selection][:settings]
    expect(settings[:operators]).to eq('["range"]')
    expect(settings).to have_key(:exclude_operators)
    expect(settings).not_to have_key(:json)
  end

  it "prints only the JSON payload on stdout, and still writes the report files" do
    Dir.mktmpdir do |dir|
      json = File.join(dir, "r.json")
      engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report_of(result_for(:killed)))
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      cli("run", "--format", "agent", "--json", json).call
      expect(JSON.parse(out.string)["status"]).to eq("complete")
      expect(File.exist?(json)).to be(true)
    end
  end

  it "keeps the classic exit code for a mixed run without --agent" do
    report = report_of(result_for(:killed), result_for(:error, replacement: "<"))
    engine = instance_double(Saboteur::Engine, guessed_tests: nil, call: report)
    allow(Saboteur::Engine).to receive(:new).and_return(engine)
    expect(cli("run", "--json", File.join(Dir.mktmpdir, "r.json")).call).to eq(0)
    expect(out.string).to include("Score: 100.0% (1/1 killed, tested subjects)")
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

  describe "errors before the agent flag is parsed" do
    it "answers a bad option that comes before --agent with a JSON error payload" do
      expect(cli("run", "--jobs", "many", "--agent").call).to eq(2)
      expect(JSON.parse(out.string)).to include("status" => "error", "verdict" => "invalid_invocation")
    end

    it "answers an unknown option, an unknown command and --format=agent with JSON too" do
      [%w[run --bogus --agent], %w[explode --agent], %w[run --nope --format=agent],
       %w[run --nope --format agent]].each do |argv|
        output = StringIO.new
        described_class.new(argv, out: output, err: StringIO.new).call
        expect(JSON.parse(output.string)).to include("exitCode" => 2)
      end
    end

    it "leaves classic output alone when --agent is not requested" do
      cli("run", "--jobs", "many").call
      expect(out.string).to eq("")
    end
  end

  describe "in a real process" do
    include E2EHelpers

    def git(dir, *args)
      Open3.capture2e("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    end

    def repository(since: nil)
      dir = File.realpath(Dir.mktmpdir("saboteur-agent-"))
      (@agent_dirs ||= []) << dir
      FileUtils.mkdir_p(File.join(dir, "config"))
      body = since ? "Saboteur.configure { |c| c.since = #{since.inspect} }" + 10.chr : ""
      File.write(File.join(dir, "config", "saboteur.rb"), body)
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib", "a.rb"), "class A; end\n")
      git(dir, "init", "-q")
      git(dir, "add", ".")
      git(dir, "commit", "-q", "-m", "first")
      dir
    end

    after { (@agent_dirs || []).each { |dir| FileUtils.remove_entry(dir) } }

    let(:script) do
      <<~RUBY
        require "saboteur"
        require "saboteur/cli"
        class Saboteur::Engine
          def initialize(*, **); end

          def call
            puts "noise from target boot"
            system("echo noise from a child process")
            $stdout.puts "noise from stdout"
            File.write("lib/new_file.rb", "x = 1\\n") if ENV["SABOTEUR_TEST_WRITE"]
            Saboteur::Report.new(results: [], subjects: [], wall_time: 0, root: Dir.pwd, seed: 1)
          end
        end
        exit Saboteur::CLI.new(ARGV).call
      RUBY
    end

    def agent_process(dir, *argv, env: {})
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), "-e", script,
                                        "--", *argv, chdir: dir)
      [out, err, status.exitstatus]
    end

    it "keeps boot, hook and child process output off stdout" do
      out, err, code = agent_process(repository, "run", "--agent")
      expect(JSON.parse(out)).to include("status" => "not_applicable")
      expect(code).to eq(3)
      expect(err).to include("noise from target boot", "noise from a child process", "noise from stdout")
    end

    it "reports the working tree as it was before the run, not after it wrote files" do
      out, = agent_process(repository, "run", "--agent", env: { "SABOTEUR_TEST_WRITE" => "1" })
      expect(JSON.parse(out)["provenance"]).to include("workingTree" => "clean", "changedFiles" => 0)
    end

    it "counts untracked files as a dirty tree, and ignores saboteur's own cache" do
      dir = repository
      FileUtils.mkdir_p(File.join(dir, ".saboteur"))
      File.write(File.join(dir, ".saboteur", "report.json"), "{}")
      out, = agent_process(dir, "run", "--agent")
      expect(JSON.parse(out)["provenance"]).to include("workingTree" => "clean")
      File.write(File.join(dir, "lib", "untracked.rb"), "y = 2\n")
      out, = agent_process(dir, "run", "--agent")
      expect(JSON.parse(out)["provenance"]).to include("workingTree" => "dirty", "changedFiles" => 1)
    end

    it "records the full commit SHA of the tree the run started on" do
      dir = repository
      out, = agent_process(dir, "run", "--agent")
      full_sha = git(dir, "rev-parse", "HEAD").first.strip
      expect(JSON.parse(out)["provenance"]["head"]).to eq(full_sha).and match(/\A\h{40,64}\z/)
    end

    it "counts every untracked file, also inside new directories" do
      dir = repository
      FileUtils.mkdir_p(File.join(dir, "lib", "fresh", "deep"))
      %w[lib/fresh/a.rb lib/fresh/b.rb lib/fresh/deep/c.rb].each { |path| File.write(File.join(dir, path), "z = 3\n") }
      out, = agent_process(dir, "run", "--agent")
      expect(JSON.parse(out)["provenance"]).to include("workingTree" => "dirty", "changedFiles" => 3)
    end

    it "takes the ref from the effective config and keeps the selection in the rerun command" do
      dir = repository(since: "HEAD")
      File.write(File.join(dir, "spec_a.rb"), "")
      out, = agent_process(dir, "run", "--agent", "--subject", "A#b", "--id", "f" * 16, "lib/a.rb")
      payload = JSON.parse(out)
      expect(payload["provenance"]).to include("ref" => "HEAD", "mode" => "replay")
      expect(payload["next"]["rerun"]).to eq("saboteur run --agent --since HEAD --subject A\\#b " \
                                             "--id #{'f' * 16} --seed 1 -- lib/a.rb")
    end
  end
end
