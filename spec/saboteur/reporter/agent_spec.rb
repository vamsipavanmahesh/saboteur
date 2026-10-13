# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "fileutils"

RSpec.describe Saboteur::Reporter::Agent do
  def provenance_with(**changes)
    described_class::Provenance.new(
      ref: "origin/main", seed: 7, head: "abc1234", working_tree: "clean", changed_files: 0, mode: "diff",
      json_report: ".saboteur/report.json", subjects: [], tests: [], sources: [], config_path: nil,
      digest: nil, cache: true, incremental: false, settings: {}, **changes
    )
  end

  let(:provenance) { provenance_with }

  def payload_for(report, provenance: self.provenance)
    JSON.parse(described_class.render(described_class.call(report, provenance)), symbolize_names: true)
  end

  def empty_report(skipped_subjects: {}, warnings: [])
    Saboteur::Report.new(results: [], subjects: [], wall_time: 0.1, root: "/tmp", seed: 7,
                         skipped_subjects: skipped_subjects, warnings: warnings)
  end

  context "when every mutant was killed" do
    let(:payload) { payload_for(report_of(result_for(:killed))) }

    it "is complete and clean, and exits 0" do
      expect(payload).to include(status: "complete", verdict: "clean", exitCode: 0, score: 1.0)
      expect(payload[:incomplete]).to eq([])
      expect(payload[:findings]).to include(survivors: 0, shown: [], omitted: 0)
    end

    it "names the provenance of the verdict" do
      expect(payload[:provenance]).to include(ref: "origin/main", seed: 7, head: "abc1234", workingTree: "clean",
                                              changedFiles: 0, mode: "diff")
    end

    it "points at the rerun command and the full report" do
      expect(payload[:next]).to eq(rerun: "saboteur run --agent --since origin/main --seed 7",
                                   fullReport: ".saboteur/report.json")
    end
  end

  context "when a mutant survived" do
    let(:payload) { payload_for(report_of(result_for(:survived), result_for(:killed, replacement: "<"))) }

    it "needs review, exits 1, and shows the finding with a replay command" do
      finding = payload[:findings][:shown].first
      expect(payload).to include(status: "complete", verdict: "survivors", exitCode: 1)
      expect(finding).to include(path: "person.rb", operator: "comparison", original: ">=", replacement: ">")
      expect(payload[:next][:replay]).to eq("saboteur run --id #{finding[:digest]} --since origin/main --seed 7")
    end

    it "includes an operator hint with an honest caveat" do
      expect(payload[:findings][:shown].first[:hint]).to start_with("try an example at the boundary")
      expect(payload[:findings][:hintCaveat]).to include("suggestions, not diagnoses")
      expect(described_class.render(payload).bytesize).to be <= described_class::BYTE_BUDGET
    end

    it "does not carry file sources" do
      expect(JSON.generate(payload)).not_to include("def adult?")
    end
  end

  it "uses coarse fallback hints but invents no hint for unknown fine operators" do
    fine = result_for(:survived)
    allow(fine).to receive(:mutation).and_return(fine.mutation.with(operator: "unknown_operator"))
    expect(payload_for(report_of(fine))[:findings][:shown].first).not_to have_key(:hint)
    coarse = result_for(:survived, coarse: true)
    expect(payload_for(report_of(coarse))[:findings][:shown].first[:hint])
      .to eq(Saboteur::Reporter::SurvivorHints::COARSE)
  end

  context "when the only survivor is accepted on the ignore list" do
    it "is clean and counts the accepted finding" do
      survivor = result_for(:survived)
      survivor.ignored = "equivalent mutant"
      payload = payload_for(report_of(survivor, result_for(:killed, replacement: "<")))
      expect(payload).to include(verdict: "clean", exitCode: 0)
      expect(payload[:findings]).to include(survivors: 0, accepted: 1)
    end
  end

  context "when coverage was missing" do
    it "is partial and exits 3, never 0" do
      report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1,
                                    root: File.dirname(person_subject.file), seed: 7,
                                    skipped_subjects: { person_subject => "no coverage" })
      payload = payload_for(report)
      expect(payload).to include(status: "partial", verdict: "incomplete", exitCode: 3)
      expect(payload[:incomplete].map { |reason| reason[:reason] }).to eq(["no_coverage"])
    end

    it "still exits 1 when a survivor is present" do
      report = Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1,
                                    root: File.dirname(person_subject.file), seed: 7,
                                    skipped_subjects: { person_subject => "no coverage" })
      expect(payload_for(report)).to include(status: "partial", verdict: "survivors", exitCode: 1)
    end
  end

  context "when the cap omitted mutants" do
    it "is partial with the omitted count" do
      warning = "Person#adult?: omitted 4 mutant(s) above max_mutants_per_method (100)"
      payload = payload_for(report_of(result_for(:killed), warnings: [warning]))
      expect(payload).to include(status: "partial", exitCode: 3)
      expect(payload[:incomplete]).to include(a_hash_including(reason: "mutant_cap", count: 4))
    end
  end

  context "when mutants errored alongside kills" do
    it "is partial, so a mixed run cannot exit 0" do
      payload = payload_for(report_of(result_for(:killed), result_for(:error, replacement: "<")))
      expect(payload).to include(status: "partial", exitCode: 3)
      expect(payload[:incomplete]).to include(a_hash_including(reason: "errors", count: 1))
    end
  end

  context "when a mutant was stopped by a timeout" do
    it "counts it as detected and says so" do
      payload = payload_for(report_of(result_for(:killed), result_for(:timeout, replacement: "<")))
      expect(payload).to include(status: "complete", exitCode: 0, timeoutCountedAsDetected: 1)
    end
  end

  context "when no mutants were selected" do
    it "is not applicable and does not claim a clean run" do
      payload = payload_for(empty_report)
      expect(payload).to include(status: "not_applicable", verdict: "not_applicable", exitCode: 3, score: nil)
    end
  end

  describe "the failure payload" do
    it "names an invalid invocation for exit 2 and a tool failure for exit 3" do
      expect(described_class.failure("jobs must be >= 1", 2)).to include(status: "error",
                                                                         verdict: "invalid_invocation", exitCode: 2)
      expect(described_class.failure("boot failed", 3)).to include(verdict: "tool_failure", exitCode: 3)
    end
  end

  describe "the byte budget" do
    def many_survivors(count, text)
      Array.new(count) do |index|
        result_for(:survived, replacement: "#{text}#{index}")
      end
    end

    it "keeps a payload with long snippets and many survivors under the budget" do
      huge = "x" * 5_000
      warnings = Array.new(20) { |index| "warning #{index} #{huge}" }
      report = report_of(*many_survivors(30, huge), warnings: warnings)
      text = described_class.render(described_class.call(report, provenance))
      expect(text.bytesize).to be <= described_class::BYTE_BUDGET
      expect(JSON.parse(text)["findings"]["survivors"]).to eq(30)
    end

    it "shows at most three findings and counts the omitted ones" do
      payload = payload_for(report_of(*many_survivors(8, "r")))
      expect(payload[:findings][:shown].size).to be <= 3
      expect(payload[:findings][:omitted]).to eq(payload[:findings][:survivors] - payload[:findings][:shown].size)
    end
  end

  describe "the commands under next" do
    let(:hostile_ref) { "$(touch${IFS}/tmp/agent-sentinel-#{Process.pid})" }

    def next_commands(**changes)
      payload_for(report_of(result_for(:survived)), provenance: provenance_with(**changes))[:next]
    end

    it "keeps a ref that holds shell syntax as one literal argument" do
      words = Shellwords.split(next_commands(ref: hostile_ref)[:rerun])
      expect(words).to include(hostile_ref)
      expect(words.each_cons(2).to_a).to include(["--since", hostile_ref])
    end

    it "does not run a ref's command substitution when the command is followed" do
      sentinel = "/tmp/agent-sentinel-#{Process.pid}"
      FileUtils.rm_f(sentinel)
      commands = next_commands(ref: hostile_ref).values_at(:rerun, :replay)
      commands.each do |command|
        output, = Open3.capture2("sh", "-c", "printf '%s\\n' #{command.delete_prefix('saboteur ')}")
        expect(output).to include(hostile_ref)
      end
      expect(File.exist?(sentinel)).to be(false)
    end

    it "escapes every other interpolated value too" do
      steps = next_commands(subjects: ["A#b; id"], tests: ["spec/a b_spec.rb"], sources: ["lib/it's.rb"],
                            config_path: "ci config.yml")
      words = Shellwords.split(steps[:rerun])
      expect(words).to include("A#b; id", "spec/a b_spec.rb", "lib/it's.rb", "ci config.yml")
    end

    it "keeps the whole selection: config, ref, subjects, tests, cache mode, digest and sources after --" do
      steps = next_commands(config_path: "ci.yml", subjects: ["A#b"], tests: ["spec/a_spec.rb"], cache: false,
                            incremental: true, sources: ["lib/a.rb"], digest: "f" * 16)
      expect(steps[:rerun]).to eq("saboteur run --agent --config ci.yml --since origin/main --subject A\\#b " \
                                  "--test spec/a_spec.rb --no-cache --incremental --id #{'f' * 16} " \
                                  "--seed 7 -- lib/a.rb")
    end

    it "leaves out a command that would be longer than the limit and says so" do
      steps = next_commands(ref: "r" * 5_000)
      expect(steps).to include(rerun: nil, replay: nil)
      expect(steps[:rerunUnavailable]).to include("longer than 1024 bytes")
    end
  end

  describe "the byte budget with unbounded inputs" do
    it "stays under budget whatever the ref, paths and selection hold" do
      huge = "x" * 100_000
      provenance = provenance_with(ref: huge, head: huge, json_report: huge, subjects: [huge] * 50,
                                   tests: [huge] * 50, sources: [huge] * 50, config_path: huge, digest: huge)
      report = report_of(result_for(:survived), result_for(:error, replacement: "<"), warnings: [huge] * 20)
      text = described_class.render(described_class.call(report, provenance))
      expect(text.bytesize).to be <= described_class::BYTE_BUDGET
      expect(JSON.parse(text)).to include("verdict" => "survivors", "exitCode" => 1)
    end

    it "falls back to a minimal payload that still fits when nothing else does" do
      provenance = provenance_with(ref: "é" * 60_000, subjects: ["é" * 60_000] * 200)
      text = described_class.render(described_class.call(report_of(result_for(:killed)), provenance))
      expect(text.bytesize).to be <= described_class::BYTE_BUDGET
    end
  end
end
