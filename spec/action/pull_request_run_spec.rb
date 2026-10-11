# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs action/run-saboteur against a stand-in saboteur command, so the
# action's own logic is tested without running mutation tests.
RSpec.describe "action/run-saboteur" do
  let(:script) { File.expand_path("../../action/run-saboteur", __dir__) }
  let(:workspace) { Dir.mktmpdir("saboteur-action") }
  let(:github_output) { File.join(workspace, "github_output") }
  let(:step_summary) { File.join(workspace, "step_summary") }
  let(:invocation_log) { File.join(workspace, "invocation.log") }
  let(:stale_report) { JSON.generate(files: { "lib/old.rb" => { mutants: [{ id: "old", status: "Killed" }] } }) }

  after { FileUtils.remove_entry(workspace) }

  def run_git(*arguments)
    _, status = Open3.capture2e("git", *arguments, chdir: workspace)
    raise "git #{arguments.join(' ')} failed" unless status.success?
  end

  def prepare_repository(shallow: false)
    run_git("init", "-q", "-b", "feature")
    run_git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "base")
    run_git("update-ref", "refs/remotes/origin/main", "HEAD")
    File.write(File.join(workspace, ".git", "shallow"), "#{`git -C #{workspace} rev-parse HEAD`.strip}\n") if shallow
  end

  # report: an array of statuses, or [status, reason] pairs, a raw String
  # written as is, or nil for "write no report".
  def mutants_from(report)
    report.each_with_index.map do |entry, index|
      status, reason = Array(entry)
      { id: index.to_s, status: status, statusReason: reason }
    end
  end

  def report_json(report)
    return report if report.is_a?(String)

    JSON.generate(schemaVersion: "2", files: { "lib/a.rb" => { mutants: mutants_from(report) } })
  end

  def write_stand_in_command(exit_status, report, log_text)
    File.write(File.join(workspace, "report-to-write.json"), report_json(report)) if report
    File.write(File.join(workspace, "log-text"), log_text)
    path = File.join(workspace, "stand-in-saboteur")
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      echo "$@" >> "#{invocation_log}"
      report_path=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--json" ]; then report_path="$2"; fi
        shift
      done
      #{report ? "mkdir -p \"$(dirname \"$report_path\")\"; cp report-to-write.json \"$report_path\"" : ':'}
      cat "#{File.join(workspace, 'log-text')}"
      exit #{exit_status}
    SH
    File.chmod(0o755, path)
    path
  end

  # Runs the action. Returns [combined output, exit status].
  def run_action(environment = {}, exit_status: 0, report: %w[Killed Killed Survived], log_text: "stand-in output\n",
                 stale: false, path: nil)
    prepare_repository unless File.directory?(File.join(workspace, ".git"))
    if stale
      FileUtils.mkdir_p(File.join(workspace, ".saboteur"))
      File.write(File.join(workspace, ".saboteur", "report.json"), stale_report)
    end
    defaults = {
      "SABOTEUR_EVENT_NAME" => "pull_request", "SABOTEUR_BASE_REF" => "main",
      "SABOTEUR_COMMAND" => write_stand_in_command(exit_status, report, log_text),
      "SABOTEUR_ARGUMENTS" => "", "SABOTEUR_FAIL_ON_SURVIVORS" => "false",
      "SABOTEUR_REPORT_PATH" => ".saboteur/report.json",
      "GITHUB_OUTPUT" => github_output, "GITHUB_STEP_SUMMARY" => step_summary
    }
    defaults["PATH"] = path if path
    stdout, status = Open3.capture2e(defaults.merge(environment), "bash", script, chdir: workspace)
    [stdout, status.exitstatus]
  end

  def outputs
    File.readlines(github_output, chomp: true).to_h { |line| line.split("=", 2) }
  end

  def invocation
    File.read(invocation_log)
  end

  describe "diff mode on a pull request" do
    it "runs against the base ref from origin" do
      _, status = run_action
      expect(status).to eq(0)
      expect(invocation).to include("run --since origin/main --json .saboteur/report.json")
    end

    it "passes extra arguments to saboteur after run" do
      run_action({ "SABOTEUR_ARGUMENTS" => "--jobs 2 --seed 7" })
      expect(invocation).to start_with("run --jobs 2 --seed 7 --since origin/main")
    end

    it "does nothing on a push event, even with a base ref" do
      output, status = run_action({ "SABOTEUR_EVENT_NAME" => "push" })
      expect(status).to eq(0)
      expect(output).to include("::notice")
      expect(File.exist?(invocation_log)).to be(false)
      expect(outputs).to include("ran" => "false")
    end

    it "does nothing without a base ref" do
      _, status = run_action({ "SABOTEUR_BASE_REF" => "" })
      expect(status).to eq(0)
      expect(File.exist?(invocation_log)).to be(false)
    end
  end

  describe "advisory and enforced mode" do
    it "is advisory by default: survivors annotate but do not fail" do
      output, status = run_action({}, exit_status: 1)
      expect(status).to eq(0)
      expect(output).to include("::warning")
      expect(outputs).to include("exit-code" => "1", "survivors" => "1", "killed" => "2")
    end

    it "fails on survivors when asked to" do
      _, status = run_action({ "SABOTEUR_FAIL_ON_SURVIVORS" => "true" }, exit_status: 1)
      expect(status).to eq(1)
    end

    it "refuses a boolean that is not exactly true or false" do
      output, status = run_action({ "SABOTEUR_FAIL_ON_SURVIVORS" => "yes" })
      expect(status).to eq(2)
      expect(output).to include("fail-on-survivors")
      expect(File.exist?(invocation_log)).to be(false)
    end

    it "always fails when saboteur itself fails" do
      output, status = run_action({}, exit_status: 3, report: nil)
      expect(status).to eq(3)
      expect(output).to include("::error")
    end
  end

  describe "the report" do
    it "labels the covered score and its denominator in the outputs and the summary" do
      run_action
      expect(outputs).to include("score" => "66.7", "report-valid" => "true", "incomplete" => "false")
      expect(File.read(step_summary)).to include("Covered score: **66.7 %**")
        .and include("killed + timeout")
    end

    it "counts timeouts as kills and reports them separately" do
      run_action({}, report: %w[Killed Timeout Survived Survived])
      expect(outputs).to include("score" => "50.0", "timeouts" => "1", "killed" => "1")
    end

    it "keeps survivors accepted by the ignore list apart from new survivors" do
      run_action({}, report: [["Killed"], ["Survived", "ignored: reason"], ["Survived"]])
      expect(outputs).to include("survivors" => "1", "accepted-survivors" => "1", "score" => "33.3")
    end

    it "reports no score when nothing was scored" do
      run_action({}, report: %w[NoCoverage])
      expect(outputs).to include("score" => "n/a", "survivors" => "0")
    end

    it "fails when saboteur exits 0 but wrote no report" do
      output, status = run_action({}, report: nil)
      expect(status).to eq(3)
      expect(output).to include("wrote no report")
      expect(outputs).to include("report-valid" => "false", "score" => "n/a")
    end

    it "does not trust a stale report left by an earlier run" do
      output, status = run_action({}, report: nil, stale: true)
      expect(status).to eq(3)
      expect(output).to include("wrote no report")
      expect(outputs).to include("killed" => "0")
    end

    it "fails when the report is not valid JSON" do
      output, status = run_action({}, report: "{ not json")
      expect(status).to eq(3)
      expect(output).to include("could not be read")
    end

    it "fails when the report has no files" do
      _, status = run_action({}, report: "{}")
      expect(status).to eq(3)
    end

    it "fails when files is a list, not an object" do
      output, status = run_action({}, report: '{"schemaVersion":"2","files":[]}')
      expect(status).to eq(3)
      expect(output).to include("files object")
    end

    it "fails when the report is not a schemaVersion 2 report" do
      _, status = run_action({}, report: '{"schemaVersion":"1","files":{}}')
      expect(status).to eq(3)
    end

    it "fails when the output holds more than one JSON document" do
      output, status = run_action({}, report: "#{report_json(%w[Killed])}\n#{report_json(%w[Survived])}")
      expect(status).to eq(3)
      expect(output).to include("exactly one JSON document")
    end

    it "fails when a file entry has no mutants list" do
      output, status = run_action({}, report: '{"schemaVersion":"2","files":{"lib/a.rb":{}}}')
      expect(status).to eq(3)
      expect(output).to include("mutants array")
    end

    it "fails when a mutant is not an object with a status" do
      _, status = run_action({}, report: '{"schemaVersion":"2","files":{"lib/a.rb":{"mutants":["Killed"]}}}')
      expect(status).to eq(3)
    end

    it "accepts a report with no files as a run that mutated nothing" do
      _, status = run_action({}, report: '{"schemaVersion":"2","files":{}}')
      expect(status).to eq(0)
      expect(outputs).to include("report-valid" => "true", "score" => "n/a")
    end

    it "fails when the old report cannot be removed" do
      FileUtils.mkdir_p(File.join(workspace, ".saboteur", "report.json", "inside"))
      output, status = run_action({})
      expect(status).to eq(3)
      expect(output).to include("could not remove the old report")
      expect(File.exist?(invocation_log)).to be(false)
    end

    it "fails when the report holds a status it does not know" do
      output, status = run_action({}, report: %w[Killed Mystery])
      expect(status).to eq(3)
      expect(output).to include("unknown mutant status")
    end

    it "fails when jq is not installed" do
      bin = File.join(workspace, "bin")
      FileUtils.mkdir_p(bin)
      %w[bash git tee mktemp awk rm cat grep cp dirname mkdir sed env].each do |tool|
        found = ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, tool) }.find do |candidate|
          File.executable?(candidate)
        end
        File.symlink(found, File.join(bin, tool)) if found
      end
      output, status = run_action({}, path: bin)
      expect(status).to eq(3)
      expect(output).to include("jq")
    end
  end

  describe "an incomplete run" do
    let(:mixed) { %w[Killed Survived RuntimeError] }

    it "is flagged but does not fail in advisory mode" do
      output, status = run_action({}, exit_status: 1, report: mixed)
      expect(status).to eq(0)
      expect(output).to include("errored or hit a resource limit")
      expect(outputs).to include("incomplete" => "true", "errors" => "1")
      expect(File.read(step_summary)).to include("Incomplete run")
    end

    it "fails when enforcing, even with no survivors" do
      _, status = run_action({ "SABOTEUR_FAIL_ON_SURVIVORS" => "true" }, report: %w[Killed RuntimeError])
      expect(status).to eq(3)
    end

    it "does not call an all-error report a run with nothing to mutate" do
      run_action({}, exit_status: 3, report: %w[RuntimeError RuntimeError])
      expect(outputs).to include("score" => "n/a", "report-valid" => "false")
    end
  end

  describe "caching" do
    it "does not pass --no-cache by default" do
      run_action
      expect(invocation).not_to include("--no-cache")
    end

    it "passes --no-cache when the cache is off, so saboteur rebuilds the coverage map" do
      run_action({ "SABOTEUR_CACHE" => "false" })
      expect(invocation).to include("run --no-cache")
    end

    it "refuses a cache value that is not exactly true or false" do
      output, status = run_action({ "SABOTEUR_CACHE" => "yes" })
      expect(status).to eq(2)
      expect(output).to include("cache must be")
      expect(File.exist?(invocation_log)).to be(false)
    end
  end

  describe "inputs the action refuses" do
    it "rejects a bare -- in arguments" do
      output, status = run_action({ "SABOTEUR_ARGUMENTS" => "--jobs 2 -- --since x" })
      expect(status).to eq(2)
      expect(output).to include("bare --")
    end

    it "refuses a report path that starts with a dash" do
      output, status = run_action({ "SABOTEUR_REPORT_PATH" => "-rf" })
      expect(status).to eq(2)
      expect(output).to include("report-path")
    end

    ["--since origin/other", "--since=origin/other", "--json other.json", "--json=other.json", "--js x",
     "--si=1"].each do |extra|
      it "rejects '#{extra}' in arguments" do
        output, status = run_action({ "SABOTEUR_ARGUMENTS" => "--jobs 2 #{extra}" })
        expect(status).to eq(2)
        expect(output).to include("::error").and include("arguments")
        expect(File.exist?(invocation_log)).to be(false)
      end
    end

    it "still accepts other long options that share a first letter" do
      _, status = run_action({ "SABOTEUR_ARGUMENTS" => "--seed 3 --subject Foo" })
      expect(status).to eq(0)
    end

    it "refuses a base ref with shell metacharacters" do
      output, status = run_action({ "SABOTEUR_BASE_REF" => "main; echo pwned" })
      expect(status).to eq(2)
      expect(output).to include("::error").and include("base-ref")
      expect(File.exist?(invocation_log)).to be(false)
    end

    it "refuses a report path with a newline" do
      output, status = run_action({ "SABOTEUR_REPORT_PATH" => "a.json\nran=true" })
      expect(status).to eq(2)
      expect(output).to include("report-path")
    end

    it "explains a missing base ref" do
      output, status = run_action({ "SABOTEUR_BASE_REF" => "release" })
      expect(status).to eq(2)
      expect(output).to include("fetch-depth: 0")
    end

    it "explains a shallow checkout" do
      prepare_repository(shallow: true)
      output, status = run_action
      expect(status).to eq(2)
      expect(output).to include("shallow").and include("fetch-depth: 0")
    end
  end

  describe "the job summary" do
    it "keeps a log that contains backticks inside its own code fence" do
      run_action({}, log_text: "before\n`````\n</details>\n# injected\n")
      summary = File.read(step_summary)
      expect(summary).to include("``````\nbefore")
      expect(summary.scan(/^`{6}$/).size).to eq(2)
    end
  end
end
