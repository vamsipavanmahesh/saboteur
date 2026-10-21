# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

# Runs action/run-baseline-gate against a stand-in saboteur command, so the
# gate's own logic is tested without running mutation tests.
RSpec.describe "action/run-baseline-gate" do
  let(:script) { File.expand_path("../../action/run-baseline-gate", __dir__) }
  let(:workspace) { Dir.mktmpdir("saboteur-baseline-gate") }
  let(:github_output) { File.join(workspace, "github_output") }
  let(:step_summary) { File.join(workspace, "step_summary") }
  let(:invocation_log) { File.join(workspace, "invocation.log") }

  after { FileUtils.remove_entry(workspace) }

  def result_json(state: "clean", exit_code: 0, new: 0, score: nil)
    categories = { "new" => Array.new(new, {}), "changed" => [], "unmatched" => [], "errors" => [] }
    JSON.generate({ "state" => state, "exit_code" => exit_code, "categories" => categories,
                    "issues" => [] }.merge(score ? { "score" => score } : {}))
  end

  # A score as saboteur writes it: the percentages, drop and verdict follow from the counts.
  def score_for(before:, now:, epsilon: 5.0)
    baseline = before[0] * 100.0 / before[1]
    current = now[0] * 100.0 / now[1]
    exceeded = (Rational(before[0] * 100, before[1]) - Rational(now[0] * 100, now[1])) > Rational(epsilon.to_s)
    { "baseline" => baseline, "current" => current, "drop" => baseline - current, "epsilon" => epsilon,
      "exceeded" => exceeded, "baseline_detected" => before[0], "baseline_scored" => before[1],
      "current_detected" => now[0], "current_scored" => now[1] }
  end

  def write_stand_in(exit_status:, stdout:)
    path = File.join(workspace, "stand-in")
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      echo "$@" >> "#{invocation_log}"
      printf '%s' '#{stdout}'
      exit #{exit_status}
    SH
    File.chmod(0o755, path)
    path
  end

  def run_gate(environment = {}, exit_status: 0, stdout: result_json)
    File.write(File.join(workspace, "baseline.json"), "{}")
    defaults = { "SABOTEUR_COMMAND" => write_stand_in(exit_status:, stdout:), "SABOTEUR_ARGUMENTS" => "",
                 "SABOTEUR_BASELINE" => "baseline.json", "SABOTEUR_BASELINE_EPSILON" => "",
                 "SABOTEUR_FAIL_ON_SURVIVORS" => "false", "GITHUB_OUTPUT" => github_output,
                 "GITHUB_STEP_SUMMARY" => step_summary }
    output, status = Open3.capture2e(defaults.merge(environment), "bash", script, chdir: workspace)
    [output, status.exitstatus]
  end

  def outputs
    File.readlines(github_output, chomp: true, encoding: "UTF-8").to_h { |line| line.split("=", 2) }
  end

  def invocation
    File.read(invocation_log, encoding: "UTF-8").strip
  end

  it "runs the baseline check with the baseline path and passes on a clean result" do
    _, status = run_gate
    expect(status).to eq(0)
    expect(invocation).to eq("baseline check --baseline baseline.json")
    expect(outputs).to include("ran" => "true", "exit-code" => "0", "baseline-state" => "clean", "baseline-new" => "0")
  end

  it "passes the epsilon through and reports the score drop in the outputs and the summary" do
    score = score_for(before: [4, 5], now: [1, 2])
    output, status = run_gate({ "SABOTEUR_BASELINE_EPSILON" => "5" }, exit_status: 1,
                                                                      stdout: result_json(state: "review_required",
                                                                                          exit_code: 1, score:))
    expect(invocation).to eq("baseline check --baseline baseline.json --epsilon 5")
    expect(status).to eq(0)
    expect(output).to include("::warning::saboteur: the score dropped by 30.0 points")
    expect(outputs).to include("baseline-state" => "review_required", "baseline-score-drop" => "30.0",
                               "baseline-score" => "80.0", "baseline-current-score" => "50.0")
    expect(File.read(step_summary, encoding: "UTF-8")).to include("a drop of 30.0 points, limit 5")
  end

  it "fails a review-needed result only when fail-on-survivors is true" do
    stdout = result_json(state: "review_required", exit_code: 1, new: 2)
    output, advisory = run_gate({}, exit_status: 1, stdout:)
    _, enforced = run_gate({ "SABOTEUR_FAIL_ON_SURVIVORS" => "true" }, exit_status: 1, stdout:)
    expect([advisory, enforced]).to eq([0, 1])
    expect(outputs).to include("baseline-new" => "2")
    expect(output).to include("Add a test that fails for each one, or accept it in config/saboteur_ignore.rb " \
                              "with a reason")
  end

  it "always fails an invalid, incompatible or incomplete check with its exit code" do
    [2, 3].each do |code|
      output, status = run_gate({}, exit_status: code, stdout: "")
      expect(status).to eq(code)
      expect(output).to include("::error::saboteur baseline check failed")
    end
  end

  it "names what exit 2 and 3 mean and points at the output" do
    output, = run_gate({}, exit_status: 2, stdout: "")
    expect(output).to include("2 means the check was invalid or incompatible with the baseline, " \
                              "3 means the check could not complete")
  end

  it "does not trust a result it cannot read" do
    output, status = run_gate({}, exit_status: 0, stdout: "not json")
    expect(status).to eq(3)
    expect(output).to include("could not be read")
  end

  describe "a result the check could not have produced" do
    let(:epsilon) { { "SABOTEUR_BASELINE_EPSILON" => "5" } }
    let(:full_score) { score_for(before: [4, 5], now: [4, 5]) }

    def unreadable(stdout, exit_status: 0, environment: {}, message: "could not be read")
      output, status = run_gate(environment, exit_status:, stdout:)
      expect(status).to eq(3), stdout
      expect(output).to include(message)
      expect(outputs).not_to include("baseline-state")
    end

    def raw(extra = {})
      JSON.generate({ "state" => "clean", "exit_code" => 0, "issues" => [],
                      "categories" => { "new" => [], "changed" => [], "unmatched" => [], "errors" => [] } }
                    .merge(extra))
    end

    it "fails closed on an unknown state, bad categories and a bad score" do
      unreadable('{"state":"nonsense","categories":{},"score":{"drop":"bad"}}')
      unreadable(result_json(state: "nonsense"))
      unreadable(raw("categories" => { "new" => 0, "changed" => [], "unmatched" => [], "errors" => [] }))
      unreadable(raw("categories" => { "new" => [], "changed" => [], "unmatched" => [] }))
      unreadable(raw("categories" => { "new" => [], "changed" => [], "unmatched" => [], "errors" => [{}] }))
    end

    it "fails closed when the state, exit status and findings disagree" do
      unreadable(result_json(state: "review_required", exit_code: 1))
      unreadable(result_json(state: "clean", exit_code: 0), exit_status: 1)
      unreadable(result_json(state: "clean", exit_code: 1))
      unreadable(result_json(state: "clean", exit_code: 0, new: 1))
      unreadable(result_json(state: "review_required", exit_code: 1), exit_status: 1)
    end

    it "requires the exit code and an empty issues list" do
      unreadable(JSON.generate(JSON.parse(raw).except("exit_code")))
      unreadable(JSON.generate(JSON.parse(raw).except("issues")))
      unreadable(raw("issues" => ["incomplete evidence"]))
      score = score_for(before: [1, 1], now: [0, 1]).merge("exceeded" => false)
      unreadable(raw("issues" => ["incomplete evidence"], "score" => score), environment: epsilon)
    end

    it "requires a complete finite score when an epsilon was given" do
      unreadable(result_json, environment: epsilon)
      unreadable(result_json(score: full_score.merge("drop" => "bad")), environment: epsilon)
      unreadable(result_json(score: full_score.except("exceeded")), environment: epsilon)
      unreadable(result_json(score: full_score.except("baseline_scored")), environment: epsilon)
      unreadable(result_json(score: full_score.merge("current" => 120.0)), environment: epsilon)
      unreadable(raw("score" => full_score).sub("80.0", "1e999"), environment: epsilon)
    end

    it "rejects a score whose arithmetic or verdict contradicts its counts" do
      lie = full_score.merge("baseline" => 80.0, "current" => 50.0, "drop" => 0.0)
      unreadable(result_json(score: lie), environment: epsilon)
      loss = score_for(before: [4, 5], now: [1, 2])
      unreadable(result_json(score: loss.merge("drop" => 0.0)), environment: epsilon)
      unreadable(result_json(score: loss.merge("exceeded" => false)), environment: epsilon)
      unreadable(result_json(score: full_score.merge("exceeded" => true)), environment: epsilon)
      unreadable(result_json(score: full_score.merge("current_detected" => 5)), environment: epsilon)
      total = score_for(before: [1, 1], now: [0, 1]).merge("exceeded" => false)
      unreadable(result_json(score: total), environment: epsilon)
    end

    it "binds the result's epsilon to the epsilon input" do
      score = score_for(before: [4, 5], now: [4, 5])
      unreadable(result_json(score: score.merge("epsilon" => 100.0)), environment: epsilon)
      unreadable(result_json(score: score.except("epsilon")), environment: epsilon)
      unreadable(result_json(score: score.merge("epsilon" => 4.9)), environment: epsilon)
    end

    it "rejects a score when no epsilon was given" do
      unreadable(result_json(score: full_score))
    end

    it "accepts the exact boundary that floating point gets wrong" do
      # 4/1000 vs 3/1000 detected is a drop of exactly 0.1 point.
      score = score_for(before: [4, 1000], now: [3, 1000], epsilon: 0.1)
      expect(score["exceeded"]).to be(false)
      _, status = run_gate({ "SABOTEUR_BASELINE_EPSILON" => "0.1" }, stdout: result_json(score:))
      expect(status).to eq(0)
      score = score_for(before: [4, 1000], now: [3, 1000], epsilon: 0.09)
      _, status = run_gate({ "SABOTEUR_BASELINE_EPSILON" => "0.09" }, exit_status: 1,
                                                                      stdout: result_json(state: "review_required",
                                                                                          exit_code: 1, score:))
      expect(status).to eq(0)
      expect(outputs).to include("baseline-state" => "review_required")
    end

    it "accepts a complete score and reports it in its own outputs" do
      _, status = run_gate(epsilon, stdout: result_json(score: full_score))
      expect(status).to eq(0)
      expect(outputs).to include("baseline-score" => "80.0", "baseline-current-score" => "80.0",
                                 "baseline-score-drop" => "0.0")
      run_gate(epsilon, exit_status: 1, stdout: result_json(state: "review_required", exit_code: 1, new: 1,
                                                            score: score_for(before: [1, 2], now: [2, 5])))
      expect(outputs).to include("baseline-score" => "50.0", "baseline-current-score" => "40.0",
                                 "baseline-score-drop" => "10.0")
    end
  end

  it "refuses a missing baseline file, a bad path, a bad epsilon and a bad boolean before running saboteur" do
    [[{ "SABOTEUR_BASELINE" => "missing.json" }, "does not exist"],
     [{ "SABOTEUR_BASELINE" => "--oops" }, "baseline may only contain"],
     [{ "SABOTEUR_BASELINE_EPSILON" => "abc" }, "baseline-epsilon must be a number"],
     [{ "SABOTEUR_BASELINE_EPSILON" => "100.5" }, "baseline-epsilon must be a number"],
     [{ "SABOTEUR_BASELINE_EPSILON" => "-1" }, "baseline-epsilon must be a number"],
     [{ "SABOTEUR_BASELINE_EPSILON" => "0.0001" }, "at most three decimals"],
     [{ "SABOTEUR_FAIL_ON_SURVIVORS" => "yes" }, "fail-on-survivors"]].each do |environment, message|
      output, status = run_gate(environment)
      expect(status).to eq(2), environment.inspect
      expect(output).to include(message)
      expect(File.exist?(invocation_log)).to be(false)
    end
  end

  it "refuses pull_request_target but runs on push and schedule" do
    output, status = run_gate({ "SABOTEUR_EVENT_NAME" => "pull_request_target" })
    expect(status).to eq(2)
    expect(output).to include("pull_request_target")
    expect(File.exist?(invocation_log)).to be(false)
    %w[push schedule pull_request].each do |event|
      _, status = run_gate({ "SABOTEUR_EVENT_NAME" => event })
      expect(status).to eq(0), event
    end
  end

  it "keeps --baseline and --epsilon (and their prefixes) out of the extra arguments" do
    ["--baseline=x", "--base", "--eps", "--epsilon", "--proposal", "--previous", "--"].each do |word|
      _, status = run_gate({ "SABOTEUR_ARGUMENTS" => "--jobs 2 #{word}" })
      expect(status).to eq(2), word
    end
    _, status = run_gate({ "SABOTEUR_ARGUMENTS" => "--jobs 2 --seed 7" })
    expect(status).to eq(0)
    expect(invocation).to eq("baseline check --baseline baseline.json --jobs 2 --seed 7")
  end

  describe "action.yml" do
    let(:action) { YAML.safe_load_file(File.join(__dir__, "..", "..", "action.yml")) }
    let(:steps) { action.fetch("runs").fetch("steps") }

    it "declares the baseline inputs as optional and empty by default" do
      %w[baseline baseline-epsilon].each do |name|
        expect(action.fetch("inputs").fetch(name)).to include("required" => false, "default" => "")
      end
    end

    it "runs the gate instead of the diff-mode run when a baseline is given" do
      gate = steps.find { |step| step["id"] == "baseline" }
      diff = steps.find { |step| step["id"] == "run" }
      expect(gate.fetch("if")).to eq("inputs.baseline != ''")
      expect(diff.fetch("if")).to eq("inputs.baseline == ''")
      expect(gate.fetch("env")).to include("SABOTEUR_BASELINE" => "${{ inputs.baseline }}",
                                           "SABOTEUR_BASELINE_EPSILON" => "${{ inputs.baseline-epsilon }}",
                                           "SABOTEUR_EVENT_NAME" => "${{ github.event_name }}")
      expect(gate.fetch("run")).to include("action/run-baseline-gate")
    end

    it "exposes the gate's state and score drop as outputs" do
      outputs = action.fetch("outputs")
      expect(outputs.fetch("baseline-state").fetch("value")).to include("steps.baseline.outputs.baseline-state")
      expect(outputs.fetch("baseline-score-drop").fetch("value")).to include("baseline-score-drop")
    end
  end

  # macOS runners ship Bash 3.2. These constructs need Bash 4 or later.
  describe "Bash 3.2 portability" do
    bash4 = Regexp.union(
      /\b(mapfile|readarray|coproc)\b/, /declare\s+-[A-Za-z]*A/, /local\s+-[A-Za-z]*[nA]\b/,
      /\$\{[A-Za-z_]+(,,|\^\^)/, /&>>/, /\|&/, /wait\s+-n\b/
    )

    it "recognizes Bash 4 constructs, so the check below can fail" do
      expect("mapfile -t parsed <<<\"$x\"").to match(bash4)
      expect("declare -A seen").to match(bash4)
      expect("name=${value,,}").to match(bash4)
      expect("while IFS= read -r line; do parsed+=(\"$line\"); done <<<\"$x\"").not_to match(bash4)
    end

    %w[run-baseline-gate run-saboteur].each do |name|
      it "keeps action/#{name} free of Bash 4 constructs" do
        lines = File.readlines(File.expand_path("../../action/#{name}", __dir__), encoding: "UTF-8")
        offenders = lines.reject { |line| line.lstrip.start_with?("#") }.grep(bash4)
        expect(offenders).to eq([])
      end
    end
  end
end
