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

  it "carries the operator policy in the provenance payload" do
    payload = payload_for(report_of(result_for(:killed)))
    expected = JSON.parse(JSON.generate(Saboteur::Config.new({}).operator_policy), symbolize_names: true)
    expect(payload.dig(:provenance, :operatorPolicy)).to eq(expected)
  end

  it "preserves selected and excluded operator lists in rerun and replay commands" do
    source = provenance_with(settings: { operators: %w[range arithmetic], exclude_operators: ["range"] })
    commands = described_class::Commands
    [commands.rerun(source), commands.replay(source, "abc")].each do |command|
      words = Shellwords.split(command)
      expect(words.each_cons(2).to_a).to include(["--operators", "range,arithmetic"],
                                                 ["--exclude-operators", "range"])
    end
  end

  # An empty list typed on the command line can clear a config-file value
  # (c.exclude_operators = [...]), so it must survive into the commands.
  it "keeps an empty operator list typed on the command line" do
    commands = described_class::Commands
    cleared = provenance_with(settings: { exclude_operators: [] }, typed_settings: [:exclude_operators])
    [commands.rerun(cleared), commands.replay(cleared, "abc", capped: false)].each do |command|
      expect(Shellwords.split(command).each_cons(2).to_a).to include(["--exclude-operators", ""])
    end
  end

  # An empty list nobody typed came from the config (or its default), which
  # the command reads again, so the flag is only noise (#317).
  it "omits empty operator lists that were not typed on the command line" do
    commands = described_class::Commands
    source = provenance_with(settings: { operators: [], exclude_operators: [] })
    [commands.rerun(source), commands.replay(source, "abc", capped: false)].each do |command|
      expect(command).not_to include("--operators", "--exclude-operators")
    end
  end

  it "keeps report paths and shards out of a replay but not out of a rerun (#1185)" do
    commands = described_class::Commands
    source = provenance_with(settings: { all: true, json_report: ".saboteur/audit-report.json",
                                         html_report: ".saboteur/audit-report.html", shard: "1/4",
                                         operators: %w[range], baseline_passes: 2 })
    replay = Shellwords.split(commands.replay(source, "abc", capped: false))
    expect(replay).to include("--operators", "range", "--baseline-passes", "2")
    expect(replay).not_to include("--json", "--html", "--shard")
    rerun = Shellwords.split(commands.rerun(source))
    expect(rerun.each_cons(2).to_a).to include(["--json", ".saboteur/audit-report.json"],
                                               ["--html", ".saboteur/audit-report.html"], ["--shard", "1/4"])
  end

  it "keeps a non-empty operator list whether or not it was typed" do
    source = provenance_with(settings: { operators: [], exclude_operators: %w[range arithmetic] })
    words = Shellwords.split(described_class::Commands.replay(source, "abc", capped: false))
    expect(words.each_cons(2).to_a).to include(["--exclude-operators", "range,arithmetic"])
    expect(words).not_to include("--operators")
  end

  it "narrows a replay to the mutant's covering spec files (#1148)" do
    report = report_of(result_for(:survived, covered_by: ["./spec/fee_spec.rb[1:2]", "./spec/fee_spec.rb[1:5]"]))
    digest = report.results.first.digest
    source = provenance_with(tests: %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb])
    command = described_class::Commands.replay(source, digest, capped: false, report: report)
    words = Shellwords.split(command)
    expect(words.each_cons(2).to_a).to include(["--test", "spec/fee_spec.rb"])
    expect(words.count("--test")).to eq(1)
  end

  it "keeps the run's tests when the survivor has no covering ids (#1148)" do
    report = report_of(result_for(:survived, covered_by: []))
    digest = report.results.first.digest
    source = provenance_with(tests: %w[spec/a_spec.rb spec/b_spec.rb])
    command = described_class::Commands.replay(source, digest, capped: false, report: report)
    words = Shellwords.split(command)
    expect(words.each_cons(2).to_a).to include(["--test", "spec/a_spec.rb"], ["--test", "spec/b_spec.rb"])
  end

  it "never emits --all when covering files narrowed the tests (#1148)" do
    report = report_of(result_for(:survived, covered_by: ["spec/fee_spec.rb[1:2]"]))
    digest = report.results.first.digest
    source = provenance_with(settings: { all: true })
    command = described_class::Commands.replay(source, digest, capped: false, report: report)
    words = Shellwords.split(command)
    expect(words).not_to include("--all")
    expect(words.each_cons(2).to_a).to include(["--test", "spec/fee_spec.rb"])
  end

  it "picks the result matching the digest, not a neighbour (#1148)" do
    other = result_for(:survived, replacement: "<", covered_by: ["./spec/other_spec.rb[1:1]"])
    survivor = result_for(:survived, covered_by: ["./spec/fee_spec.rb[1:2]"])
    report = report_of(other, survivor)
    command = described_class::Commands.replay(provenance_with, survivor.digest, capped: false, report: report)
    words = Shellwords.split(command)
    expect(words.each_cons(2).to_a).to include(["--test", "spec/fee_spec.rb"])
    expect(words).not_to include("spec/other_spec.rb")
  end

  it "keeps the run's tests when no result matches the digest (#1148)" do
    report = report_of(result_for(:survived, covered_by: ["./spec/fee_spec.rb[1:2]"]))
    source = provenance_with(tests: %w[spec/a_spec.rb])
    command = described_class::Commands.replay(source, "f" * 16, capped: false, report: report)
    expect(Shellwords.split(command).each_cons(2).to_a).to include(["--test", "spec/a_spec.rb"])
  end

  it "records a whole-suite run as a bare --all so rerun and replay keep that scope" do
    source = provenance_with(ref: nil, settings: { all: true })
    commands = described_class::Commands
    [commands.rerun(source), commands.replay(source, "abc")].each do |command|
      expect(Shellwords.split(command)).to include("--all")
    end
  end

  it "never emits --all alongside named tests, however the provenance was recorded" do
    source = provenance_with(ref: nil, settings: { all: true }, tests: ["spec/a_spec.rb"])
    words = Shellwords.split(described_class::Commands.rerun(source))
    expect(words).not_to include("--all")
    expect(words.each_cons(2).to_a).to include(["--test", "spec/a_spec.rb"])
  end

  it "keeps the run budget and baseline passes in rerun and replay commands (#245)" do
    source = provenance_with(settings: { max_duration: 600.0, max_duration_ok: true, baseline_passes: 3 })
    commands = described_class::Commands
    [commands.rerun(source), commands.replay(source, "abc")].each do |command|
      words = Shellwords.split(command)
      expect(words.each_cons(2)).to include(["--max-duration", "600.0"], ["--baseline-passes", "3"])
      expect(words).to include("--max-duration-ok")
    end
  end

  it "preserves an explicit --no-max-duration-ok over a config true in rerun and replay commands (#245)" do
    source = provenance_with(settings: { max_duration_ok: false })
    commands = described_class::Commands
    [commands.rerun(source), commands.replay(source, "abc")].each do |command|
      words = Shellwords.split(command)
      expect(words).to include("--no-max-duration-ok")
      expect(words).not_to include("--max-duration-ok")
    end
    positive = provenance_with(settings: { max_duration_ok: true })
    [commands.rerun(positive), commands.replay(positive, "abc")].each do |command|
      words = Shellwords.split(command)
      expect(words).to include("--max-duration-ok")
      expect(words).not_to include("--no-max-duration-ok")
    end
    unset = provenance_with(settings: {})
    expect(Shellwords.split(commands.rerun(unset)).grep(/max-duration-ok/)).to eq([])
  end

  it "keeps CLI-only replay-driving switches in rerun and replay commands (#261)" do
    source = provenance_with(settings: { allow_hazardous: true, allow_focus: true })
    commands = described_class::Commands
    [commands.rerun(source), commands.replay(source, "abc")].each do |command|
      words = Shellwords.split(command)
      expect(words).to include("--allow-hazardous", "--allow-focus")
    end
  end

  it "leaves an over-long replay command out for the agent but prints it whole in the text footer (#261)" do
    long_tests = Array.new(60) { |i| "spec/feature number #{i}/a_spec.rb" }
    source = provenance_with(ref: nil, tests: long_tests, sources: [])
    command = described_class::Commands.replay(source, "abc", capped: false)
    expect(command.bytesize).to be > described_class::Commands::MAX_BYTES
    expect(Shellwords.split(command)).to include("--test", "spec/feature number 3/a_spec.rb")
    expect(described_class::Commands.replay(source, "abc")).to be_nil
  end

  it "emits a runnable rerun for an inferred run without sources: --test stands alone" do
    source = provenance_with(ref: nil, tests: ["spec/a_spec.rb"], sources: [])
    words = Shellwords.split(described_class::Commands.rerun(source))
    expect(words.each_cons(2).to_a).to include(["--test", "spec/a_spec.rb"])
    expect(words).not_to include("--")
  end

  context "when every mutant was killed" do
    let(:payload) { payload_for(report_of(result_for(:killed))) }

    it "is complete and clean, and exits 0" do
      expect(payload).to include(status: "complete", verdict: "clean", exitCode: 0, score: 1.0)
      expect(payload[:incomplete]).to eq([])
      expect(payload[:findings]).to include(survivors: 0, shown: [], omitted: 0)
    end

    it "splits kills into assertion, crash and cause-not-recorded" do
      payload = payload_for(report_of(result_for(:killed, kill_cause: "assertion"),
                                      result_for(:killed, replacement: "<", kill_cause: "NoMethodError"),
                                      result_for(:killed, replacement: "<=")))
      expect(payload[:killCauses]).to eq(assertionKills: 1, crashKills: 1, unclassifiedKills: 1)
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
      expect(finding).to include(path: "person.rb", line: 2, endLine: 2, coarse: false,
                                 operator: "comparison", original: ">=", replacement: ">")
      # The slice is the whitelist: the raw entry's internals must not leak (#192 dogfood).
      expect(finding.keys).not_to include(:edits, :changedLines)
      expect(payload[:next][:replay]).to eq("saboteur run --id #{finding[:digest]} --since origin/main --seed 7")
    end

    it "carries the survivor's classification, as data (#192)" do
      shown = payload[:findings][:shown]
      covered = payload_for(report_of(result_for(:survived, covered_by: %w[t1])))[:findings][:shown].first
      expect(covered[:classification]).to eq("missing_test")
      # Unlabeled means the key is absent from the JSON, never null.
      expect(shown.first).not_to have_key(:classification)
    end

    it "gives the finding a testHint with the boundary case, as data" do
      hint = payload[:findings][:shown].first[:testHint]
      expect(hint).to include(kind: "boundary", case: "left == right")
      expect(hint[:text]).to start_with("try an example at the boundary")
    end

    it "gives a coarse survivor of an unlisted operator the method-result hint" do
      coarse = payload_for(report_of(result_for(:survived, coarse: true)))
      expect(coarse[:findings][:shown].first[:testHint]).to eq(
        kind: "method_result", text: "try asserting this method's result or its effect"
      )
    end

    it "appends the equivalence-confirmation hint for a chain_removal survivor (#264)" do
      payload = payload_for(report_of(result_for(:survived, operator: "chain_removal")))
      expect(payload[:findings][:shown].first[:hint])
        .to include("if you confirm the shorter chain is equivalent across the intended inputs")
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

    it "marks a run with an unreadable included file as incomplete" do
      failures = [Saboteur::Engine::Diagnostics::DiscoveryFailure.new(file: "/r/a.rb", reason: "unreadable")]
      report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1,
                                    root: File.dirname(person_subject.file), seed: 7,
                                    discovery_failures: failures)
      payload = payload_for(report)
      expect(payload).to include(status: "partial", verdict: "incomplete", exitCode: 3)
      expect(payload[:incomplete]).to include(a_hash_including(reason: "unreadable", count: 1,
                                                               meaning: "included untracked files could not be " \
                                                                        "read; their subjects were not covered"))
    end

    it "counts each discovery failure kind separately in a mixed run" do
      failures = [Saboteur::Engine::Diagnostics::DiscoveryFailure.new(file: "/r/a.rb", reason: "unreadable"),
                  Saboteur::Engine::Diagnostics::DiscoveryFailure.new(file: "/r/b.rb",
                                                                      reason: "invalid_file_syntax")]
      report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1,
                                    root: File.dirname(person_subject.file), seed: 7,
                                    discovery_failures: failures)
      payload = payload_for(report)
      expect(payload[:incomplete]).to contain_exactly(
        a_hash_including(reason: "unreadable", count: 1,
                         meaning: "included untracked files could not be read; their subjects were not covered"),
        a_hash_including(reason: "invalid_file_syntax", count: 1,
                         meaning: "included files did not parse; their subjects were not discovered")
      )
    end

    it "marks a run with an unparseable included file as incomplete" do
      failures = [Saboteur::Engine::Diagnostics::DiscoveryFailure.new(file: "/r/a.rb",
                                                                      reason: "invalid_file_syntax")]
      report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1,
                                    root: File.dirname(person_subject.file), seed: 7,
                                    discovery_failures: failures)
      payload = payload_for(report)
      expect(payload).to include(status: "partial", verdict: "incomplete", exitCode: 3)
      expect(payload[:incomplete]).to include(a_hash_including(reason: "invalid_file_syntax", count: 1,
                                                               meaning: "included files did not parse; their " \
                                                                        "subjects were not discovered"))
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

    it "lists the files chosen by reference: their count, the first three, each clipped" do
      referenced = (1..5).to_h { |n| ["lib/#{n}#{'x' * 200}.rb", ["spec/s#{n}_spec.rb"]] }
      payload = payload_for(report_of(result_for(:survived)), provenance: provenance_with(referenced: referenced))
      listed = payload.dig(:provenance, :selection, :referenced)

      expect(listed[:count]).to eq(5)
      expect(listed[:first].map { |file| file[0, 5] }).to eq(%w[lib/1 lib/2 lib/3])
      expect(listed[:first].map(&:size)).to all(eq(123))
    end

    it "flags a survivor in a file whose specs were chosen by reference" do
      survivor = result_for(:survived)
      flagged = payload_for(report_of(survivor, referenced: { "person.rb" => ["spec/p_spec.rb"] }))
      other = payload_for(report_of(survivor, referenced: { "other.rb" => ["spec/o_spec.rb"] }))

      expect(flagged[:findings][:shown].first).to include(specsByReference: true)
      expect(other[:findings][:shown].first).not_to have_key(:specsByReference)
      expect(payload_for(report_of(survivor))[:findings][:shown].first).not_to have_key(:specsByReference)
    end

    it "lists no referenced files by default" do
      payload = payload_for(report_of(result_for(:survived)))

      expect(payload.dig(:provenance, :selection, :referenced)).to eq(count: 0, first: [])
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
  it "bounds completeness when any inline candidates were suppressed, including all-suppressed runs" do
    [[], [result_for(:killed)]].each do |results|
      report = Saboteur::Report.new(results: results, subjects: [person_subject], wall_time: 1,
                                    root: File.dirname(person_subject.file),
                                    inline_suppressions: [{ reason: "elsewhere" }])
      payload = payload_for(report)
      expect(payload).to include(status: "partial", verdict: "incomplete", exitCode: 3)
      meaning = "candidates were suppressed by inline directives; see the full report audit"
      expect(payload[:incomplete]).to include(a_hash_including(reason: "inline_suppressed", count: 1, meaning: meaning))
      expect(payload[:next][:fullReport]).to eq(".saboteur/report.json")
    end
  end
end
