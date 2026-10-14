# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::Checks::Rspec do
  def real(name)
    PreflightSupport.fixture_json(name)
  end

  def copy(document)
    Marshal.load(Marshal.dump(document))
  end

  # Returns the JSON the real RSpec would write to the harness-owned pipe.
  def check_with(status, document, **flags)
    text = document.is_a?(String) ? document : JSON.generate(document)
    runner = PreflightSupport::ScriptedRunner.new do |argv|
      PreflightSupport::ScriptedRunner.new.result(argv, status, "", data: (text if document), **flags)
    end
    described_class.new(name: "suite", command_runner: runner, paths: ["spec/a_spec.rb"]).call
  end

  let(:clean) { real("rspec_clean.json") }
  let(:mixed) { real("rspec_mixed.json") }

  it "passes a real clean report with exit 0 (valid control)" do
    expect(check_with(0, clean).status).to eq(:passed)
  end

  it "fails a real report with failures, naming the failed examples and the raw report" do
    result = check_with(1, mixed)
    expect([result.status, result.details.first]).to match([:failed, a_string_including("fails")])
    expect(result.details.last).to start_with("raw report: ")
  end

  it "counts pending examples without failing on them" do
    pending_only = copy(mixed)
    pending_only["examples"].reject! { |example| example["status"] == "failed" }
    pending_only["summary"].merge!("example_count" => 2, "failure_count" => 0)
    expect(check_with(0, pending_only).status).to eq(:passed)
  end

  it "is incomplete for negative counts that look like a pass" do
    bad = copy(clean)
    bad["summary"].merge!("example_count" => -1, "errors_outside_of_examples_count" => -1)
    expect(check_with(0, bad).status).to eq(:incomplete)
  end

  it "is incomplete when the example list does not match the summary" do
    bad = copy(clean)
    bad["examples"] = []
    expect(check_with(0, bad).status).to eq(:incomplete)
    bad = copy(mixed)
    bad["summary"]["failure_count"] = 0
    expect(check_with(0, bad).status).to eq(:incomplete)
  end

  it "is incomplete for an unknown example status" do
    bad = copy(clean)
    bad["examples"].first["status"] = "mystery"
    expect(check_with(0, bad).status).to eq(:incomplete)
  end

  it "is incomplete when spec files failed to load or zero examples ran" do
    bad = copy(clean)
    bad["summary"]["errors_outside_of_examples_count"] = 1
    expect(check_with(1, bad).status).to eq(:incomplete)
    bad = copy(clean)
    bad.merge!("examples" => [])
    bad["summary"].merge!("example_count" => 0)
    expect(check_with(0, bad).status).to eq(:incomplete)
  end

  it "is incomplete when the exit status and summary disagree" do
    expect(check_with(0, mixed).status).to eq(:incomplete)
    expect(check_with(1, clean).status).to eq(:incomplete)
  end

  it "is incomplete for a missing file, malformed JSON, wrong types, a missing examples list or duplicate keys" do
    expect(check_with(0, nil).status).to eq(:incomplete)
    expect(check_with(0, "{").status).to eq(:incomplete)
    expect(check_with(0, clean.merge("summary" => "x")).status).to eq(:incomplete)
    expect(check_with(0, clean.except("examples")).status).to eq(:incomplete)
    duplicated = JSON.generate(clean).sub("{", '{"summary":{},')
    expect(check_with(0, duplicated).status).to eq(:incomplete)
  end

  it "is incomplete when the command timed out, was killed, left processes or could not start" do
    expect(check_with(0, clean, timed_out: true).status).to eq(:incomplete)
    expect(check_with(-1, clean, spawn_error: "missing").status).to eq(:incomplete)
    expect(check_with(-1, mixed, signal: 9).status).to eq(:incomplete)
    expect(check_with(0, clean, stray_processes: true).status).to eq(:incomplete)
  end

  it "passes the requested paths to RSpec" do
    runner = PreflightSupport::ScriptedRunner.new do |argv|
      PreflightSupport::ScriptedRunner.new.result(argv, 0, "", data: JSON.generate(clean))
    end
    described_class.new(name: "x", command_runner: runner, paths: ["spec/a_spec.rb"]).call
    expect(runner.calls.first).to start_with(%w[bundle exec rspec spec/a_spec.rb])
    expect(runner.calls.first).to end_with(["--require", "/harness/rspec_fd3_shim.rb", "--format", "json"])
  end
end
