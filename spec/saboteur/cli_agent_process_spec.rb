# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "stringio"
require "tmpdir"

# Agent mode run inside this process, so the coverage map sees these specs. The
# engine is stubbed; the CLI, the working-tree snapshot and the payload are real.
RSpec.describe Saboteur::CLI, "agent mode in this process" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:root) { File.realpath(Dir.mktmpdir("saboteur-cli-")) }

  after { FileUtils.remove_entry(root) }

  def cli(*argv)
    described_class.new(argv, out:, err:)
  end

  def not_include_usage
    satisfy("not be the usage text") { |message| message != described_class::USAGE }
  end

  def git(*args)
    Open3.capture2e("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: root)
  end

  def repository(config: "")
    FileUtils.mkdir_p(File.join(root, "lib"))
    File.write(File.join(root, "lib", "a.rb"), "class A; end\n")
    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config", "saboteur.rb"), config)
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "first")
  end

  def run_in_repository(*argv)
    allow(Saboteur::Engine).to receive(:new).and_return(engine_double(guessed_tests: nil,
                                                                      call: report_of))
    Dir.chdir(root) { cli(*argv).call }
    JSON.parse(out.string)
  end

  describe "provenance" do
    before { repository }

    it "describes a whole-project run on a clean tree, with the full SHA" do
      provenance = run_in_repository("run", "--agent")["provenance"]
      expect(provenance).to include("mode" => "full", "workingTree" => "clean", "changedFiles" => 0, "ref" => nil,
                                    "head" => git("rev-parse", "HEAD").first.strip)
    end

    it "takes the ref and the diff mode from the effective config" do
      File.write(File.join(root, "config", "saboteur.rb"), "Saboteur.configure { |c| c.since = \"HEAD\" }\n")
      git("commit", "-q", "-am", "config")
      File.write(File.join(root, "lib", "probe.rb"), "class Probe; end\n")
      provenance = run_in_repository("run", "--agent")["provenance"]
      expect(provenance).to include("mode" => "diff", "ref" => "HEAD")
    end

    it "records named sources and keeps them in the rerun command" do
      payload = run_in_repository("run", "--agent", "lib/a.rb")
      expect(payload["provenance"]).to include("mode" => "files")
      expect(payload["provenance"]["selection"]["sources"]).to eq("count" => 1, "first" => ["lib/a.rb"])
      expect(payload["next"]["rerun"]).to end_with("-- lib/a.rb")
    end

    it "records a replay digest" do
      payload = run_in_repository("run", "--agent", "--id", "f" * 16)
      expect(payload["provenance"]).to include("mode" => "replay")
      expect(payload["provenance"]["selection"]["digest"]).to eq("f" * 16)
    end

    it "does not count saboteur's own cache and report paths as source changes" do
      FileUtils.mkdir_p(File.join(root, ".saboteur"))
      File.write(File.join(root, ".saboteur", "results.json"), "{}")
      FileUtils.mkdir_p(File.join(root, "out"))
      File.write(File.join(root, "out", "r.json"), "{}")
      File.write(File.join(root, "out", "r.html"), "<html>")
      payload = run_in_repository("run", "--agent", "--json", "out/r.json", "--html", "out/r.html")
      expect(payload["provenance"]).to include("workingTree" => "clean", "changedFiles" => 0)
    end

    it "does count a source file that is not committed" do
      File.write(File.join(root, "lib", "new.rb"), "y = 2\n")
      expect(run_in_repository("run", "--agent")["provenance"]).to include("workingTree" => "dirty",
                                                                           "changedFiles" => 1)
    end

    it "writes the HTML report, quietly" do
      html = File.join(root, "r.html")
      run_in_repository("run", "--agent", "--html", html)
      expect(File.exist?(html)).to be(true)
      expect(out.string).not_to include("HTML report")
    end
  end

  describe "answers when the output is not agent output" do
    it "puts the usage text in the payload for an unknown command" do
      expect(cli("explode", "--agent").call).to eq(2)
      expect(JSON.parse(out.string)["message"]).to eq(described_class::USAGE)
    end

    it "does not answer with JSON for --format text or for a value that merely is 'agent'" do
      expect(cli("run", "--bogus", "--format", "text").call).to eq(2)
      expect(cli("run", "--bogus", "--test", "agent").call).to eq(2)
      expect(out.string).to eq("")
    end

    it "carries the parser's message, not the usage text, for a bad option" do
      cli("run", "--agent", "--jobs", "many").call
      expect(JSON.parse(out.string)["message"]).to include("invalid argument").and not_include_usage
    end
  end

  it "describes --agent in the option list" do
    agent_switch = cli.parser.top.list.find { |switch| switch.long.include?("--agent") }
    expect(agent_switch.desc).to eq(["Same as --format agent"])
  end

  describe "the agent exit codes in help" do
    it "are listed under the run exit codes and under no other command" do
      help = Saboteur::Help.new(option_lines: cli.option_lines)
      expect(help.overview.scan("With --agent the codes are stricter").size).to eq(1)
      expect(help.command("run")).to include("With --agent the codes are stricter")
      expect(help.command("doctor")).not_to include("--agent")
    end
  end

  describe "moving stdout to stderr while the engine runs" do
    let(:out_path) { File.join(root, "stdout.txt") }
    let(:err_path) { File.join(root, "stderr.txt") }
    let(:out_file) { File.open(out_path, "w") }
    let(:err_file) { File.open(err_path, "w") }

    around do |example|
      original_out = $stdout
      original_err = $stderr
      $stdout = out_file
      $stderr = err_file
      example.run
    ensure
      $stdout = original_out
      $stderr = original_err
      out_file.close
      err_file.close
    end

    def moved(&)
      cli.send(:stdout_on_stderr, &)
    end

    it "sends what the block prints to stderr and puts stdout back afterwards" do
      $stdout.print("before ")
      moved { $stdout.puts("inside") }
      $stdout.puts("after")
      $stdout.flush
      $stderr.flush
      expect(File.read(out_path)).to eq("before after\n")
      expect(File.read(err_path)).to eq("inside\n")
    end

    it "returns what the block returns, and restores stdout when it raises" do
      expect(moved { :value }).to eq(:value)
      expect { moved { raise "boom" } }.to raise_error("boom")
      $stdout.puts("restored")
      $stdout.flush
      expect(File.read(out_path)).to eq("restored\n")
    end

    it "closes the saved copy of stdout" do
      File.open(File::NULL, "w") do |saved|
        allow(out_file).to receive(:dup).and_return(saved)
        moved { nil }
        expect(saved).to be_closed
      end
    end

    it "raises the original error when stdout cannot be copied, without masking it" do
      allow(out_file).to receive(:dup).and_raise(IOError, "dup failed")
      ran = false
      expect { moved { ran = true } }.to raise_error(IOError, "dup failed")
      expect(ran).to be(false)
    end
  end
end
