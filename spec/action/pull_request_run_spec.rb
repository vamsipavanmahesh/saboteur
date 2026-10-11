# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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
  let(:default_statuses) { %w[Killed Killed Survived] }

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

  def write_stand_in_command(exit_status)
    path = File.join(workspace, "stand-in-saboteur")
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      echo "$@" >> "#{invocation_log}"
      report_path=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--json" ]; then report_path="$2"; fi
        shift
      done
      mkdir -p "$(dirname "$report_path")"
      cp "#{File.join(workspace, 'stand-in-report.json')}" "$report_path"
      echo "stand-in saboteur output"
      exit #{exit_status}
    SH
    File.chmod(0o755, path)
    path
  end

  def write_stand_in_report(statuses)
    mutants = statuses.each_with_index.map do |status, index|
      { id: index.to_s, status: status, statusReason: nil }
    end
    File.write(File.join(workspace, "stand-in-report.json"),
               JSON.generate(files: { "lib/a.rb" => { mutants: mutants } }))
  end

  def run_action(environment = {}, exit_status: 0, statuses: default_statuses)
    prepare_repository unless File.directory?(File.join(workspace, ".git"))
    write_stand_in_report(statuses)
    defaults = {
      "SABOTEUR_BASE_REF" => "main", "SABOTEUR_COMMAND" => write_stand_in_command(exit_status),
      "SABOTEUR_ARGUMENTS" => "", "SABOTEUR_FAIL_ON_SURVIVORS" => "false",
      "SABOTEUR_REPORT_PATH" => ".saboteur/report.json",
      "GITHUB_OUTPUT" => github_output, "GITHUB_STEP_SUMMARY" => step_summary
    }
    stdout, status = Open3.capture2e(defaults.merge(environment), "bash", script, chdir: workspace)
    [stdout, status.exitstatus]
  end

  def outputs
    File.readlines(github_output, chomp: true).to_h { |line| line.split("=", 2) }
  end

  it "runs diff mode against the base ref from origin" do
    _, status = run_action
    expect(status).to eq(0)
    expect(File.read(invocation_log)).to include("run --since origin/main --json .saboteur/report.json")
  end

  it "passes extra arguments to saboteur" do
    run_action({ "SABOTEUR_ARGUMENTS" => "--jobs 2 --seed 7" })
    expect(File.read(invocation_log)).to include("--jobs 2 --seed 7")
  end

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

  it "always fails when saboteur itself fails" do
    output, status = run_action({}, exit_status: 3)
    expect(status).to eq(3)
    expect(output).to include("::error")
  end

  it "reports the score in the outputs and the step summary" do
    run_action
    expect(outputs).to include("score" => "66.7")
    expect(File.read(step_summary)).to include("66.7 %").and include("Mutation testing")
  end

  it "reports no score when nothing was mutated" do
    run_action({}, statuses: [])
    expect(outputs).to include("score" => "n/a", "survivors" => "0")
  end

  it "does nothing outside a pull request" do
    output, status = run_action({ "SABOTEUR_BASE_REF" => "" })
    expect(status).to eq(0)
    expect(output).to include("::notice")
    expect(File.exist?(invocation_log)).to be(false)
    expect(outputs).to include("ran" => "false")
  end

  it "refuses a base ref with shell metacharacters" do
    output, status = run_action({ "SABOTEUR_BASE_REF" => "main; echo pwned" })
    expect(status).to eq(2)
    expect(output).to include("::error").and include("base-ref")
    expect(File.exist?(invocation_log)).to be(false)
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
