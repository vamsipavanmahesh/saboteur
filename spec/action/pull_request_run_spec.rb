# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

# Runs action/run-saboteur against a stand-in saboteur command, so the
# action's own logic is tested without running mutation tests.
RSpec.describe "action/run-saboteur" do
  # The action reads the report with jq, so every example but the one that
  # removes jq needs it on the runner: skip with a reason instead of failing.
  before do |example|
    skip "jq is not installed" unless example.metadata[:without_jq] || system("command -v jq > /dev/null 2>&1")
  end

  let(:script) { File.expand_path("../../action/run-saboteur", __dir__) }
  let(:workspace) { Dir.mktmpdir("saboteur-action") }
  let(:github_output) { File.join(workspace, "github_output") }
  let(:step_summary) { File.join(workspace, "step_summary") }
  let(:invocation_log) { File.join(workspace, "invocation.log") }
  let(:stale_report) { JSON.generate(files: { "lib/old.rb" => { mutants: [{ id: "old", status: "Killed" }] } }) }

  after do
    FileUtils.remove_entry(workspace)
    FileUtils.rm_rf(@bare_origin) if @bare_origin
  end

  def run_git(*arguments)
    _, status = Open3.capture2e("git", *arguments, chdir: workspace)
    raise "git #{arguments.join(' ')} failed" unless status.success?
  end

  def prepare_repository(shallow: false)
    run_git("init", "-q", "-b", "feature")
    commit_empty("root")
    commit_empty("event base")
    @base_sha = `git -C #{workspace} rev-parse HEAD`.strip
    run_git("branch", "main")
    commit_empty("moved base tip")
    run_git("update-ref", "refs/remotes/origin/main", "HEAD")
    run_git("checkout", "-q", "-b", "pr", @base_sha)
    commit_empty("pr merge")
    run_git("update-ref", "refs/pull/7/merge", "HEAD")
    @head_sha = `git -C #{workspace} rev-parse HEAD`.strip
    File.write(File.join(workspace, ".git", "shallow"), "#{@head_sha}\n") if shallow
  end

  def prepare_real_shallow_repository
    bare = create_bare_origin
    build_origin_history
    publish_origin_refs(bare)
    checkout_shallow_pr_merge(bare)
  end

  def create_bare_origin
    path = File.join(File.dirname(workspace), "saboteur-action-origin-#{Process.pid}-#{object_id}.git")
    @bare_origin = path
    _, status = Open3.capture2e("git", "init", "--bare", "-q", path)
    raise "could not create bare origin" unless status.success?

    _, status = Open3.capture2e("git", "--git-dir", path, "symbolic-ref", "HEAD", "refs/heads/main")
    raise "could not set bare origin HEAD" unless status.success?

    path
  end

  def build_origin_history
    run_git("init", "-q", "-b", "feature")
    commit_empty("root")
    commit_empty("event base")
    @base_sha = `git -C #{workspace} rev-parse HEAD`.strip
    run_git("branch", "main")
    commit_empty("moved base tip")
    @moved_tip = `git -C #{workspace} rev-parse HEAD`.strip
    run_git("checkout", "-q", "-b", "pr", @base_sha)
    commit_empty("PR change one")
    commit_empty("PR change two")
    commit_empty("pr merge")
    @pr_merge = `git -C #{workspace} rev-parse HEAD`.strip
  end

  def commit_empty(message)
    run_git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q",
            "--allow-empty", "-m", message)
  end

  def publish_origin_refs(bare)
    run_git("push", "-q", bare, "#{@moved_tip}:refs/heads/main", "#{@pr_merge}:refs/pull/7/merge")
  end

  def checkout_shallow_pr_merge(bare)
    FileUtils.rm_rf(File.join(workspace, ".git"))
    _, status = Open3.capture2e("git", "clone", "--no-checkout", "--depth=1", "file://#{bare}", workspace)
    raise "could not shallow-clone local origin" unless status.success?

    _, status = Open3.capture2e(
      "git", "-C", workspace, "fetch", "--no-tags", "--depth=1", "origin", "refs/pull/7/merge"
    )
    raise "could not fetch shallow PR merge ref" unless status.success?

    run_git("checkout", "-q", "--detach", "FETCH_HEAD")
    @head_sha = `git -C #{workspace} rev-parse HEAD`.strip
    shallow_file = File.join(workspace, ".git", "shallow")
    File.write(shallow_file, "#{@head_sha}\n") unless File.exist?(shallow_file)
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
    copy_report = report ? 'mkdir -p "$(dirname "$report_path")"; cp report-to-write.json "$report_path"' : ":"
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      echo "$@" >> "#{invocation_log}"
      report_path=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--json" ]; then report_path="$2"; fi
        shift
      done
      #{copy_report}
      cat "#{File.join(workspace, 'log-text')}"
      exit #{exit_status}
    SH
    File.chmod(0o755, path)
    path
  end

  # Runs the action. Returns [combined output, exit status].
  def report_with_findings(findings, truncated: 0, statuses: nil, version: 1, accepted: [],
                           accepted_truncated: 0)
    statuses ||= findings.map { "Survived" }
    JSON.generate(schemaVersion: "2",
                  files: { "lib/a.rb" => { mutants: mutants_from(statuses) } },
                  saboteur: { findings: { version:, survivorsTruncated: truncated,
                                          acceptedTruncated: accepted_truncated,
                                          survivors: findings, accepted: } })
  end

  def finding(overrides = {})
    { digest: "698e4b7eca600583", path: "lib/a.rb", line: 3, endLine: 3, subject: "Cart#total",
      operator: "comparison", original: ">=", replacement: ">", coarse: false }.merge(overrides)
  end

  def run_action(environment = {}, exit_status: 0, report: %w[Killed Killed Survived], log_text: "stand-in output\n",
                 stale: false, path: nil)
    prepare_repository unless File.directory?(File.join(workspace, ".git"))
    write_stale_report if stale
    defaults = action_environment(exit_status, report, log_text, path)
    stdout, status = Open3.capture2e(defaults.merge(environment), "bash", script, chdir: workspace)
    [stdout, status.exitstatus]
  end

  def write_stale_report
    FileUtils.mkdir_p(File.join(workspace, ".saboteur"))
    File.write(File.join(workspace, ".saboteur", "report.json"), stale_report)
  end

  def action_environment(exit_status, report, log_text, path)
    {
      "SABOTEUR_EVENT_NAME" => "pull_request", "SABOTEUR_BASE_SHA" => @base_sha,
      "SABOTEUR_EXPECTED_HEAD_SHA" => @head_sha, "GITHUB_REF" => "refs/pull/7/merge",
      "SABOTEUR_COMMAND" => write_stand_in_command(exit_status, report, log_text),
      "SABOTEUR_ARGUMENTS" => "", "SABOTEUR_FAIL_ON_SURVIVORS" => "false",
      "SABOTEUR_REPORT_PATH" => ".saboteur/report.json",
      "GITHUB_OUTPUT" => github_output, "GITHUB_STEP_SUMMARY" => step_summary,
      "GITHUB_RUN_ID" => "", "GITHUB_SERVER_URL" => "", "GITHUB_REPOSITORY" => "",
      "GIT_SHIM_STATE" => File.join(workspace, "git-shim-state"),
      "GIT_SHIM_FETCHES" => File.join(workspace, "git-shim-fetches"),
      "GIT_SHIM_BASE_SHA" => @base_sha,
      "PATH" => build_git_shim(path)
    }
  end

  def build_git_shim(path)
    bin = File.join(workspace, "git-bin")
    FileUtils.mkdir_p(bin)
    real_git = ENV.fetch("PATH").split(File::PATH_SEPARATOR)
                  .map { |dir| File.join(dir, "git") }
                  .find { |candidate| File.executable?(candidate) }
    File.write(File.join(bin, "git"), git_shim_source(real_git))
    File.chmod(0o755, File.join(bin, "git"))
    [bin, path || ENV.fetch("PATH")].join(File::PATH_SEPARATOR)
  end

  def git_shim_template
    <<~SH
      #!/usr/bin/env bash
      case "$*" in
          "merge-base "*)
            if [ "${GIT_SHIM_FORCE_NO_MERGE_BASE:-}" = 1 ] || [ "${GIT_SHIM_LAST_INCREMENT:-}" = 1 ]; then
              count=0
              [ -f "$GIT_SHIM_STATE" ] && count=$(cat "$GIT_SHIM_STATE")
              count=$((count + 1)); echo "$count" > "$GIT_SHIM_STATE"
              [ "${GIT_SHIM_FORCE_NO_MERGE_BASE:-}" = 1 ] && exit 1
              if [ "$count" -le 20 ]; then exit 1; fi
              echo "$GIT_SHIM_BASE_SHA"
              exit 0
            fi
            ;;
          "fetch --no-tags --depth=1 origin "*)
            echo base >> "$GIT_SHIM_FETCHES"
            [ "${GIT_SHIM_FAIL_BASE:-}" = 1 ] && exit 1
            [ "${GIT_SHIM_FORCE_NO_MERGE_BASE:-}" = 1 ] || [ "${GIT_SHIM_LAST_INCREMENT:-}" = 1 ] && exit 0
            ;;
          "fetch --no-tags --deepen=100 origin "*)
            echo deepen >> "$GIT_SHIM_FETCHES"
            [ "${GIT_SHIM_FAIL_DEEPEN:-}" = 1 ] && exit 1
            [ "${GIT_SHIM_FORCE_NO_MERGE_BASE:-}" = 1 ] || [ "${GIT_SHIM_LAST_INCREMENT:-}" = 1 ] && exit 0
            ;;
        esac
        exec "__REAL_GIT__" "$@"
    SH
  end

  def git_shim_source(real_git)
    git_shim_template.gsub("__REAL_GIT__", real_git)
  end

  def outputs
    File.readlines(github_output, chomp: true, encoding: "UTF-8").to_h { |line| line.split("=", 2) }
  end

  def invocation
    File.read(invocation_log, encoding: "UTF-8")
  end

  describe "diff mode on a pull request" do
    it "runs against the exact base SHA from the pull_request event" do
      _, status = run_action
      expect(status).to eq(0)
      expect(invocation).to include("run --since #{@base_sha} --json .saboteur/report.json")
    end

    it "passes extra arguments to saboteur after run" do
      run_action({ "SABOTEUR_ARGUMENTS" => "--jobs 2 --seed 7" })
      expect(invocation).to start_with("run --jobs 2 --seed 7 --since #{@base_sha}")
    end

    it "runs on workflow_dispatch with the base SHA from the dispatch input" do
      _, status = run_action({ "SABOTEUR_EVENT_NAME" => "workflow_dispatch", "GITHUB_REF" => @head_sha })
      expect(status).to eq(0)
      expect(invocation).to include("run --since #{@base_sha} --json .saboteur/report.json")
    end

    it "requires the merge ref on pull_request but not on workflow_dispatch" do
      output, status = run_action({ "GITHUB_REF" => "refs/heads/feature" })
      expect(status).to eq(2)
      expect(output).to include("cannot deepen the pull request checkout safely")
      _, dispatch_status = run_action({ "SABOTEUR_EVENT_NAME" => "workflow_dispatch", "GITHUB_REF" => @head_sha })
      expect(dispatch_status).to eq(0)
      expect(invocation).to include("run --since #{@base_sha}")
    end

    it "does nothing on a push event, even with a base SHA" do
      output, status = run_action({ "SABOTEUR_EVENT_NAME" => "push" })
      expect(status).to eq(0)
      expect(output).to include("::notice")
      expect(File.exist?(invocation_log)).to be(false)
      expect(outputs).to include("ran" => "false")
    end

    it "fails closed when the event base SHA is missing" do
      output, status = run_action({ "SABOTEUR_BASE_SHA" => "" })
      expect(status).to eq(2)
      expect(output).to include("did not provide its base SHA")
      expect(File.exist?(invocation_log)).to be(false)
    end

    it "rejects a malformed event base SHA before running saboteur" do
      output, status = run_action({ "SABOTEUR_BASE_SHA" => "main" })
      expect(status).to eq(2)
      expect(output).to include("40-character base SHA")
      expect(File.exist?(invocation_log)).to be(false)
    end

    it "checks the exact event checkout SHA before running saboteur" do
      output, status = run_action({ "SABOTEUR_EXPECTED_HEAD_SHA" => "b" * 40 })
      expect(status).to eq(2)
      expect(output).to include("does not match the pull_request event checkout SHA")
      expect(File.exist?(invocation_log)).to be(false)
    end

    it "rechecks the merge base after the twentieth and final successful deepen" do
      prepare_repository(shallow: true)
      output, status = run_action({ "GIT_SHIM_LAST_INCREMENT" => "1" }, exit_status: 0)
      expect(status).to eq(0)
      deepens = File.readlines(File.join(workspace, "git-shim-fetches")).count { |line| line == "deepen\n" }
      expect(deepens).to eq(20)
      expect(output).not_to include("after fetching 2,000")
    end

    it "stops at the explicit bound when no merge base is found" do
      prepare_repository(shallow: true)
      output, status = run_action({ "GIT_SHIM_FORCE_NO_MERGE_BASE" => "1" })
      expect(status).to eq(2)
      expect(output).to include("after fetching 2,000 pull-request commits")
      deepens = File.readlines(File.join(workspace, "git-shim-fetches")).count { |line| line == "deepen\n" }
      expect(deepens).to eq(20)
      expect(File.exist?(invocation_log)).to be(false)
    end

    it "fails closed for complete unrelated histories" do
      prepare_repository
      tree = `git -C #{workspace} rev-parse HEAD^{tree}`.strip
      unrelated_sha, status = Open3.capture2(
        "git", "-C", workspace, "-c", "user.name=t", "-c", "user.email=t@example.com",
        "commit-tree", tree, "-m", "unrelated"
      )
      raise "could not create unrelated test commit" unless status.success?

      run_git("update-ref", "refs/remotes/origin/unrelated", unrelated_sha.strip)
      output, status = run_action({ "SABOTEUR_BASE_SHA" => unrelated_sha.strip })
      # A complete checkout has no history boundary to deepen: missing merge
      # base is a terminal scope error, never an invitation to full-scan.
      expect(status).to eq(2)
      expect(output).to include("no merge base exists")
      expect(File.exist?(invocation_log)).to be(false)
    end

    it "rejects a non-PR ref rather than deepening an arbitrary ref" do
      output, status = run_action({ "GITHUB_REF" => "refs/heads/main" })
      expect(status).to eq(2)
      expect(output).to include("cannot deepen the pull request checkout safely")
      expect(File.exist?(invocation_log)).to be(false)
    end

    it "deepens a real shallow PR checkout to the exact event base while the branch tip has moved" do
      prepare_real_shallow_repository
      _, status = run_action
      expect(status).to eq(0)
      expect(invocation).to include("--since #{@base_sha}")
      expect(invocation).not_to include("--since origin/main")
      expect(`git -C #{workspace} rev-parse refs/remotes/origin/main`.strip).not_to eq(@base_sha)
      expect(`git -C #{workspace} merge-base #{@base_sha} HEAD`.strip).to eq(@base_sha)
    end

    it "fails closed when the base commit cannot be fetched" do
      output, status = run_action({ "SABOTEUR_BASE_SHA" => "b" * 40, "GIT_SHIM_FAIL_BASE" => "1" })
      expect(status).to eq(2)
      expect(output).to include("could not fetch the pull request's exact base SHA")
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

    {
      2 => "bad configuration (exit 2)",
      3 => "could not verify (exit 3)",
      4 => "the --max-duration budget ran out (exit 4)",
      5 => "the baseline suite is red (exit 5)",
      70 => "saboteur crashed (exit 70"
    }.each do |exit_status, phrase|
      it "names the exit #{exit_status} state in the summary instead of a zeroed tally (#1209)" do
        run_action({}, exit_status: exit_status, report: nil)
        summary = File.read(step_summary, encoding: "UTF-8")
        expect(summary).to include(phrase)
        expect(summary).not_to include("No mutant was scored")
      end
    end

    it "explains exit 4 in the error annotation (#1209)" do
      output, = run_action({}, exit_status: 4, report: nil)
      expect(output).to include("4 means the --max-duration budget stopped the run early")
    end
  end

  describe "the report" do
    it "labels the covered score and its denominator in the outputs and the summary" do
      run_action
      expect(outputs).to include("score" => "66.7", "report-valid" => "true", "incomplete" => "false")
      expect(File.read(step_summary, encoding: "UTF-8")).to include("Covered score: **66.7 %**")
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

    it "fails when jq is not installed", :without_jq do
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
      expect(File.read(step_summary, encoding: "UTF-8")).to include("Incomplete run")
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

  describe "timeout and error gates" do
    it "passes no gate flag when the inputs are empty" do
      run_action({ "SABOTEUR_MAX_TIMEOUTS" => "", "SABOTEUR_MAX_ERRORS" => "" })
      expect(invocation).not_to include("--max-")
    end

    it "passes the limits to saboteur after the extra arguments and before --since" do
      run_action({ "SABOTEUR_ARGUMENTS" => "--jobs 2", "SABOTEUR_MAX_TIMEOUTS" => "3", "SABOTEUR_MAX_ERRORS" => "5%" })
      expect(invocation).to start_with("run --jobs 2 --max-timeouts 3 --max-errors 5% --since #{@base_sha}")
    end

    it "passes --max-duration after the extra arguments and before --since (#1210)" do
      run_action({ "SABOTEUR_ARGUMENTS" => "--jobs 2", "SABOTEUR_MAX_DURATION" => "10m" })
      expect(invocation).to start_with("run --jobs 2 --max-duration 10m --since #{@base_sha}")
    end

    it "passes no --max-duration flag when the input is empty (#1210)" do
      run_action({ "SABOTEUR_MAX_DURATION" => "" })
      expect(invocation).not_to include("--max-duration")
    end

    it "accepts a limit of exactly 100% and a zero-padded count" do
      _, status = run_action({ "SABOTEUR_MAX_ERRORS" => "100%", "SABOTEUR_MAX_TIMEOUTS" => "007" })
      expect(status).to eq(0)
    end

    ["abc", "-1", "1.5", "5%%", "101%", "3 4", "%"].each do |value|
      it "refuses the max-timeouts value #{value.inspect} before running saboteur" do
        output, status = run_action({ "SABOTEUR_MAX_TIMEOUTS" => value })
        expect(status).to eq(2)
        expect(output).to include("max-timeouts must be a count")
        expect(File.exist?(invocation_log)).to be(false)
      end
    end

    it "names max-errors when that limit is malformed" do
      output, status = run_action({ "SABOTEUR_MAX_ERRORS" => "many" })
      expect(status).to eq(2)
      expect(output).to include("max-errors must be a count")
    end

    it "calls a failed gate a gate failure when no mutant survived" do
      output, status = run_action({ "SABOTEUR_MAX_TIMEOUTS" => "0" }, exit_status: 1, report: %w[Killed Timeout])
      expect(status).to eq(0)
      expect(output).to include("so a gate failed")
      expect(output).not_to include("0 mutants survived")
    end

    it "fails the step on a failed gate when enforcing" do
      _, status = run_action({ "SABOTEUR_MAX_TIMEOUTS" => "0", "SABOTEUR_FAIL_ON_SURVIVORS" => "true" },
                             exit_status: 1, report: %w[Killed Timeout])
      expect(status).to eq(1)
    end

    it "keeps errors within max-errors from failing an incomplete run" do
      output, status = run_action({ "SABOTEUR_MAX_ERRORS" => "2", "SABOTEUR_FAIL_ON_SURVIVORS" => "true" },
                                  report: %w[Killed RuntimeError])
      expect(status).to eq(0)
      expect(output).to include("errored or hit a resource limit")
      expect(outputs).to include("incomplete" => "true")
    end

    it "still fails an incomplete run when max-errors is not set" do
      _, status = run_action({ "SABOTEUR_FAIL_ON_SURVIVORS" => "true" }, report: %w[Killed RuntimeError])
      expect(status).to eq(3)
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

    it "refuses a report path with a newline" do
      output, status = run_action({ "SABOTEUR_REPORT_PATH" => "a.json\nran=true" })
      expect(status).to eq(2)
      expect(output).to include("report-path")
    end
  end

  describe "findings on the pull request" do
    it "annotates each survivor with its file, line and what changed" do
      output, status = run_action({}, exit_status: 1,
                                      report: report_with_findings([finding], statuses: %w[Killed Survived]))
      expect(status).to eq(0)
      annotation = "::warning file=lib/a.rb,line=3,endLine=3,title=Mutant survived%3A comparison::" \
                   "Cart#total: >= became > (698e4b7eca600583)."
      expect(status).to eq(0)
      expect(output).to include(annotation)
    end

    it "escapes source text and paths in the annotation command" do
      output, = run_action({}, report: report_with_findings([finding(path: "lib/a,b.rb",
                                                                     original: "100%\n:ok")]))
      expect(output).to include("file=lib/a%2Cb.rb").and include("100%25%0A:ok")
    end

    it "lists the findings in the summary and counts what the bound left out" do
      both = [finding, finding(digest: "fb645ab834991e60")]
      report = report_with_findings(both, truncated: 3, statuses: %w[Killed Survived Survived])
      run_action({ "GITHUB_SERVER_URL" => "https://github.example", "GITHUB_REPOSITORY" => "o/r",
                   "GITHUB_RUN_ID" => "42" }, report:)
      summary = File.read(step_summary, encoding: "UTF-8")
      expect(summary).to include(
        "- `lib/a.rb`:3 `comparison`: `>=` became `>` in `Cart#total` (`698e4b7eca600583`)"
      )
        .and include("Showing the first 2 of 5 surviving mutants")
        .and include("[`saboteur-report` artifact](https://github.example/o/r/actions/runs/42)")
    end

    it "names the artifact without a link when the run's location is unknown" do
      run_action({}, report: report_with_findings([finding]))
      expect(File.read(step_summary, encoding: "UTF-8")).to include("kept as this run's `saboteur-report` artifact")
    end

    it "keeps a backtick in source text inside a wider code span" do
      run_action({}, report: report_with_findings([finding(replacement: "a`b")]))
      expect(File.read(step_summary, encoding: "UTF-8")).to include("`` a`b ``")
    end

    it "folds a multi-line edit onto one summary line" do
      run_action({}, report: report_with_findings([finding(original: "alpha\nbeta")]))
      expect(File.read(step_summary, encoding: Encoding::UTF_8)).to include("`alpha⏎beta`")
    end

    it "keeps working with a report that has no findings section" do
      output, status = run_action({}, exit_status: 1, report: report_json(%w[Killed Survived]))
      expect(status).to eq(0)
      expect(output).to include("::warning")
      expect(output).not_to include("file=")
      expect(File.read(step_summary, encoding: "UTF-8")).not_to include("Surviving mutants, coarse mutants first")
    end

    it "keeps an empty original aligned, so a pure insertion does not shift fields" do
      output, = run_action({}, report: report_with_findings([finding(original: "", replacement: "raise")]))
      expect(output).to include("became raise (698e4b7eca600583)")
      expect(File.read(step_summary, encoding: "UTF-8"))
        .to include("- `lib/a.rb`:3 `comparison`: (empty) became `raise`")
    end

    it "widens the code span past any run of backticks in the source text" do
      run_action({}, report: report_with_findings([finding(replacement: "a``b")]))
      expect(File.read(step_summary, encoding: "UTF-8")).to include("``` a``b ```")
    end

    it "ignores a findings section from another version" do
      output, = run_action({}, report: report_with_findings([finding], version: 2))
      expect(output).not_to include("file=")
    end

    it "skips a finding whose digest could smuggle a workflow command" do
      output, = run_action({}, report: report_with_findings([finding(digest: "abc%0A::error::injected")]))
      expect(output).to include("skipped 1 findings whose fields did not match")
      expect(output).not_to include("file=")
      expect(output).not_to include("::error::injected")
    end

    it "rejects an inverted range and a mistyped field instead of coercing them" do
      output, = run_action({}, report: report_with_findings([finding(line: 5, endLine: 2)]))
      expect(output).to include("skipped 1 findings whose fields did not match")
      expect(output).not_to include("file=")
      output, = run_action({}, report: report_with_findings([finding(line: "3")]))
      expect(output).not_to include("file=")
    end

    it "counts only the findings it actually emits" do
      good = finding
      bad = finding(digest: "not a digest!")
      output, = run_action({}, report: report_with_findings([good, bad], statuses: %w[Killed Survived Survived]))
      expect(output.scan(/^::warning file=/).size).to eq(1)
      expect(output).to include("skipped 1 findings whose fields did not match")
      expect(File.read(step_summary, encoding: "UTF-8")).to include("1 of the findings were skipped")
    end

    it "treats a fractional truncation count as malformed findings" do
      output, = run_action({}, report: report_with_findings([finding], truncated: 1.5))
      expect(output).to include("not in the version 1 format this action reads")
      expect(output).not_to include("file=")
    end

    it "keeps an empty replacement and a trailing newline aligned" do
      output, = run_action({}, report: report_with_findings([finding(original: "x", replacement: "")]))
      expect(output).to include("x became  (698e4b7eca600583)")
      run_action({}, report: report_with_findings([finding(replacement: "line\n")]))
      expect(File.read(step_summary, encoding: Encoding::UTF_8)).to include("`line⏎`")
    end

    it "skips a finding whose path could leave the repository" do
      output, = run_action({}, report: report_with_findings([finding(path: "../secret.rb")]))
      expect(output).to include("skipped 1 findings whose fields did not match")
      expect(output).not_to include("file=")
    end

    it "widens the span past three backticks and keeps HTML-looking text literal" do
      run_action({}, report: report_with_findings([finding(replacement: "a```b", subject: "<b>x</b>")]))
      summary = File.read(step_summary, encoding: "UTF-8")
      expect(summary).to include("```` a```b ````").and include("`<b>x</b>`")
    end

    it "annotates at most ten survivors even when the report lists more" do
      many = (1..11).map { |n| finding(digest: format("%016x", n), line: n, endLine: n) }
      output, = run_action({}, report: report_with_findings(many, truncated: 2,
                                                                  statuses: ["Killed"] + (["Survived"] * 11)))
      expect(output.scan(/^::warning file=/).size).to eq(10)
      expect(File.read(step_summary, encoding: "UTF-8")).to include("Showing the first 10 of 13 surviving mutants")
    end

    it "lists accepted survivors apart, with their reason, and no notes" do
      ok = finding(digest: "fb645ab834991e60", reason: "equivalent")
      output, = run_action({}, report: report_with_findings([finding], accepted: [ok],
                                                                       statuses: %w[Killed Survived]))
      expect(output.scan(/^::warning file=/).size).to eq(1)
      summary = File.read(step_summary, encoding: "UTF-8")
      expect(summary).to include("### Accepted survivors (on the ignore list)")
        .and include("accepted: `equivalent` (`fb645ab834991e60`)")
    end

    it "diagnoses a findings section that is present but unreadable" do
      report = JSON.generate(schemaVersion: "2", files: { "lib/a.rb" => { mutants: mutants_from(%w[Survived]) } },
                             saboteur: { findings: { version: 1, survivors: "broken" } })
      output, = run_action({}, exit_status: 1, report:)
      expect(output).to include("findings section is not in the version 1 format this action reads")
      expect(output).not_to include("file=")
    end

    it "keeps this run's report artifact even when the saboteur step fails" do
      action = YAML.safe_load_file(File.join(__dir__, "..", "..", "action.yml"))
      upload = action.fetch("runs").fetch("steps").find { |step| step["uses"].to_s.include?("upload-artifact") }
      expect(upload.fetch("if")).to include("always()").and include("report-valid")
      expect(upload.fetch("with").fetch("name")).to include("github.job").and include("strategy.job-index")
    end

    it "lets a repeated invocation pick its own artifact name, and tells the summary the same one" do
      action = YAML.safe_load_file(File.join(__dir__, "..", "..", "action.yml"))
      expect(action.fetch("inputs").fetch("artifact-name")).to include("required" => false)
      upload = action.fetch("runs").fetch("steps").find { |step| step["uses"].to_s.include?("upload-artifact") }
      run_step = action.fetch("runs").fetch("steps").find { |step| step["id"] == "run" }
      summary_name = run_step.fetch("env").fetch("SABOTEUR_ARTIFACT_NAME")
      expect(summary_name).to eq(upload.fetch("with").fetch("name"))
      expect(summary_name).to include("inputs.artifact-name")
    end

    it "keeps working when the findings section is malformed" do
      report = JSON.generate(schemaVersion: "2", files: { "lib/a.rb" => { mutants: mutants_from(%w[Survived]) } },
                             saboteur: { findings: "not an object" })
      output, status = run_action({}, exit_status: 1, report:)
      expect(status).to eq(0)
      expect(output).not_to include("file=")
    end
  end

  describe "the job summary" do
    it "keeps a log that contains backticks inside its own code fence" do
      run_action({}, log_text: "before\n`````\n</details>\n# injected\n")
      summary = File.read(step_summary, encoding: "UTF-8")
      expect(summary).to include("``````\nbefore")
      expect(summary.scan(/^`{6}$/).size).to eq(2)
    end
  end
end
