# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

# Exact-value specs for the agent payload: clip limits, boundaries, texts and the
# budget fallbacks. Each one pins a value that a small change would alter.
RSpec.describe Saboteur::Reporter::Agent, "exact values" do
  def provenance_with(**changes)
    described_class::Provenance.new(
      ref: "origin/main", seed: 7, head: "abc1234", working_tree: "clean", changed_files: 0, mode: "diff",
      json_report: ".saboteur/report.json", subjects: [], tests: [], sources: [], config_path: nil,
      digest: nil, cache: true, incremental: false, settings: {}, **changes
    )
  end

  def payload_for(report, **changes)
    described_class.call(report, provenance_with(**changes))
  end

  def finding_with(**changes)
    { digest: "d" * 16, path: "lib/a.rb", line: 3, endLine: 3, subject: "A#b", operator: "comparison",
      original: ">=", replacement: ">", coarse: false, edits: [] }.merge(changes)
  end

  def with_findings(*findings, ordering: "order")
    allow(Saboteur::Reporter::Findings).to receive(:build)
      .and_return(survivors: findings, survivorsTruncated: 0, accepted: [], acceptedTruncated: 0, ordering: ordering)
  end

  # Text whose every position differs, so a clip that starts one character late shows.
  def letters(length)
    Array.new(length) { |index| ("a".."z").to_a[index % 26] }.join
  end

  let(:survivor_report) { report_of(result_for(:survived)) }

  describe "payload text and numbers" do
    it "defines the score and rounds it to four places" do
      report = report_of(result_for(:killed), result_for(:killed, replacement: "<"),
                         result_for(:survived, replacement: "!="))
      payload = payload_for(report)
      expect(payload[:score]).to eq(0.6667)
      expect(payload[:scoreDefinition]).to eq(
        "(killed + timeout) / (killed + survived + timeout); null when nothing was tested"
      )
    end

    it "names every count in camel case" do
      report = report_of(result_for(:killed), result_for(:survived, replacement: "<"),
                         result_for(:timeout, replacement: "!="), result_for(:resource_limit, replacement: "=="),
                         result_for(:error, replacement: "<="), result_for(:skipped, replacement: "+", reason: "x"))
      expect(payload_for(report)[:counts]).to eq(killed: 1, survived: 1, timeout: 1, resourceLimit: 1, error: 1,
                                                 skipped: 1, ranAtLoad: 0, unreachable: 0, unverified: 0, executed: 5)
    end

    it "counts ignored survivors apart from live ones" do
      ignored = result_for(:survived, replacement: "<")
      ignored.ignored = "equivalent"
      findings = payload_for(report_of(result_for(:survived), ignored))[:findings]
      expect(findings).to include(survivors: 1, accepted: 1)
    end

    it "counts what it did not show: all, some, none" do
      many = Array.new(8) { |index| result_for(:survived, replacement: "r#{index}") }
      expect(payload_for(report_of(*many))[:findings]).to include(survivors: 8, omitted: 5)
      two = [result_for(:survived), result_for(:survived, replacement: "<")]
      expect(payload_for(report_of(*two))[:findings]).to include(survivors: 2, omitted: 0)
    end

    it "gives the ordering of the findings it lists" do
      with_findings(finding_with, ordering: "coarse first")
      expect(payload_for(survivor_report)[:findings][:ordering]).to eq("coarse first")
    end
  end

  describe "reasons a run is incomplete" do
    def reasons(report)
      payload_for(report)[:incomplete]
    end

    it "names the subjects a --fail-fast stop left unrun" do
      stop = Saboteur::EarlyStop.new(reason: "fail_fast", unreached: %w[A#x B#y], truncated: [], unverified: [])
      report = Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1.0,
                                    root: File.dirname(person_subject.file), seed: 1, early_stop: stop)
      expect(reasons(report)).to include(
        reason: "fail_fast", count: 2,
        meaning: "selected subjects did not run because --fail-fast stopped the run"
      )
      whole = Array(reasons(report_of(result_for(:survived)))).map { |reason| reason[:reason] }
      expect(whole).not_to include("fail_fast")
    end

    it "marks a run partial when the budget stopped a subject mid-way and no subject was skipped (#245)" do
      stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: [],
                                     truncated: [{ subject: "Person#adult?", omitted: 3 }], unverified: [])
      report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                    root: File.dirname(person_subject.file), seed: 1, early_stop: stop)
      expect(reasons(report)).to include(
        reason: "max_duration_truncated", count: 3,
        meaning: "mutants omitted inside subjects that stopped mid-way because the --max-duration budget " \
                 "stopped the run"
      )
      expect(payload_for(report)[:status]).to eq("partial")
    end

    it "reports unverified mutants as an incomplete reason, budget or flaky check (#296, #1167)" do
      report = Saboteur::Report.new(results: [result_for(:unverified)], subjects: [person_subject], wall_time: 1.0,
                                    root: File.dirname(person_subject.file), seed: 1)
      expect(reasons(report)).to include(
        reason: "unverified", count: 1,
        meaning: "mutants left unverified by a spent --max-duration budget or a flaky-check " \
                 "disagreement; their kills are not confirmed"
      )
      expect(payload_for(report)).to include(status: "partial", verdict: "incomplete")
    end

    it "says what no coverage means, adding skipped subjects and skipped mutants" do
      report = Saboteur::Report.new(results: [result_for(:skipped, reason: "no coverage"),
                                              result_for(:skipped, replacement: "<", reason: "no coverage")],
                                    subjects: [person_subject], wall_time: 1, root: "/tmp", seed: 7,
                                    skipped_subjects: { person_subject => "no coverage" })
      expect(reasons(report)).to eq([{ reason: "no_coverage", count: 3,
                                       meaning: "subjects or mutants had no covering test" }])
    end

    it "counts covered block methods and refinements as unsupported, not as missing coverage" do
      reports = ["defined inside a block", "refinements"].map do |reason|
        Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1,
                             root: "/tmp", seed: 7, skipped_subjects: { person_subject => reason })
      end
      reports.each do |report|
        expect(reasons(report)).to eq([{ reason: "unsupported", count: 1,
                                         meaning: "subjects were skipped as unsupported (for example defined " \
                                                  "inside a block); no mutant was judged" }])
        expect(payload_for(report)).to include(status: "partial", verdict: "incomplete", exitCode: 3)
      end
    end

    it "classifies loaded-before-coverage skips as preloaded, never unsupported (#688)" do
      report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1,
                                    root: "/tmp", seed: 7,
                                    skipped_subjects: { person_subject => Saboteur::Selection::CoverageMap::PRELOADED })
      expect(reasons(report)).to eq([{ reason: "preloaded", count: 1,
                                       meaning: "files loaded before coverage started; their subjects could not " \
                                                "be attributed to tests; no mutant was judged" }])
    end

    it "keeps no coverage, load-only, preloaded and unsupported subject skips apart" do
      first, second, third, fourth = subjects_in("class K\n  def a; end\n  def b; end\n  def c; end\n  " \
                                                 "def d; end\nend\n")
      skipped = { first => "no coverage", second => "defined inside a block",
                  third => Saboteur::Selection::CoverageMap::RAN_AT_LOAD,
                  fourth => Saboteur::Selection::CoverageMap::PRELOADED }
      report = Saboteur::Report.new(results: [result_for(:killed)], subjects: skipped.keys, wall_time: 1,
                                    root: "/tmp", seed: 7, skipped_subjects: skipped)
      expect(reasons(report).to_h { |reason| [reason[:reason], reason[:count]] })
        .to eq("no_coverage" => 1, "unsupported" => 1, "ran_at_load" => 1, "preloaded" => 1)
    end

    it "never calls unjudged load-only or unreachable mutants complete" do
      %i[ran_at_load unreachable].each do |status|
        payload = payload_for(report_of(result_for(status)))
        expect(payload).to include(status: "partial", verdict: "incomplete", exitCode: 3)
        expect(payload[:incomplete].map { |reason| reason[:reason] }).to eq([status.to_s])
      end
    end

    it "counts load-only subjects apart from no-coverage skips with exact meanings" do
      load_reason = Saboteur::Selection::CoverageMap::RAN_AT_LOAD
      report = Saboteur::Report.new(results: [result_for(:ran_at_load), result_for(:unreachable)],
                                    subjects: [person_subject], wall_time: 1, root: "/tmp",
                                    skipped_subjects: { person_subject => load_reason })
      expect(reasons(report)).to eq([
                                      { reason: "ran_at_load", count: 2,
                                        meaning: "code ran only at load; no mutant was judged" },
                                      { reason: "unreachable", count: 1,
                                        meaning: "tests did not call the replacement definition" }
                                    ])
    end

    it "says what a capped method means" do
      warnings = ["A#b: omitted 4 mutant(s) above max_mutants_per_method (100)", "C#d: omitted 2 mutant(s) above x"]
      expect(reasons(report_of(result_for(:killed), warnings: warnings))).to eq(
        [{ reason: "mutant_cap", count: 6, meaning: "mutants omitted by max_mutants_per_method" }]
      )
    end

    it "marks a shard partial and names the mutants assigned elsewhere" do
      shard = Saboteur::Engine::Shard.parse("2/4")
      allow(shard).to receive(:planned_count).and_return(10)
      allow(shard).to receive(:selected_count).and_return(3)
      allow(shard).to receive(:to_h).and_return(index: 2, of: 4, selected: 3, planned: 10,
                                                inventoryDigest: "a" * 64, partial: true)
      report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1,
                                    root: "/tmp", seed: 7, shard: shard)
      expect(reasons(report)).to include(
        reason: "shard", count: 7, meaning: "planned mutants assigned to other shards"
      )
      payload = payload_for(report)
      expect(payload).to include(status: "partial", shard: shard.to_h)
      expect(payload_for(report_of(result_for(:killed)))).not_to have_key(:shard)
    end

    it "keeps every shard partial, even one that selected its whole inventory or none of it" do
      full = Saboteur::Engine::Shard.parse("1/2")
      allow(full).to receive(:planned_count).and_return(1)
      allow(full).to receive(:selected_count).and_return(1)
      allow(full).to receive(:to_h).and_return(index: 1, of: 2, selected: 1, planned: 1,
                                               inventoryDigest: "a" * 64, partial: true)
      full_report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject],
                                         wall_time: 1, root: "/tmp", seed: 7, shard: full)
      expect(reasons(full_report)).to include(
        reason: "shard", count: 0, meaning: "planned mutants assigned to other shards"
      )
      expect(payload_for(full_report)).to include(status: "partial", verdict: "incomplete", exitCode: 3)

      empty = Saboteur::Engine::Shard.parse("2/2")
      allow(empty).to receive(:planned_count).and_return(1)
      allow(empty).to receive(:selected_count).and_return(0)
      allow(empty).to receive(:to_h).and_return(index: 2, of: 2, selected: 0, planned: 1,
                                                inventoryDigest: "b" * 64, partial: true)
      empty_report = Saboteur::Report.new(results: [], subjects: [], wall_time: 1,
                                          root: "/tmp", seed: 7, shard: empty)
      expect(payload_for(empty_report)).to include(status: "partial", verdict: "incomplete", exitCode: 3)
    end

    it "says what errors and resource limits mean" do
      report = report_of(result_for(:killed), result_for(:error, replacement: "<"),
                         result_for(:resource_limit, replacement: "=="))
      expect(reasons(report)).to eq(
        [{ reason: "errors", count: 1, meaning: "mutants errored; their verdict did not hold up" },
         { reason: "resource_limit", count: 1, meaning: "mutants hit the memory or process cap" }]
      )
    end

    it "is partial, not not_applicable, when there are no results but subjects had no coverage" do
      report = Saboteur::Report.new(results: [], subjects: [person_subject], wall_time: 1, root: "/tmp", seed: 7,
                                    skipped_subjects: { person_subject => "no coverage" })
      expect(payload_for(report)).to include(status: "partial", verdict: "incomplete", exitCode: 3)
    end
  end

  describe "clipping" do
    it "keeps a ref of exactly 120 characters and clips one of 121" do
      expect(payload_for(survivor_report, ref: letters(120))[:provenance][:ref]).to eq(letters(120))
      expect(payload_for(survivor_report, ref: letters(121))[:provenance][:ref]).to eq("#{letters(120)}...")
    end

    it "keeps a setting of exactly 120 characters and clips one of 121" do
      exact = payload_for(survivor_report, settings: { reeval: letters(120) })
      clipped = payload_for(survivor_report, settings: { reeval: letters(121) })
      expect(exact[:provenance][:selection][:settings]).to eq(reeval: letters(120))
      expect(clipped[:provenance][:selection][:settings]).to eq(reeval: "#{letters(120)}...")
    end

    it "keeps a head of exactly 64 characters and clips one of 65" do
      expect(payload_for(survivor_report, head: letters(64))[:provenance][:head]).to eq(letters(64))
      expect(payload_for(survivor_report, head: letters(65))[:provenance][:head]).to eq("#{letters(64)}...")
    end

    it "shows the first three of each selection list, clipped at 120, with the full count" do
      list = [letters(120), letters(121), "u", "v"]
      selection = payload_for(survivor_report, subjects: list, tests: list, sources: list,
                                               config_path: letters(121), digest: "f" * 16)[:provenance][:selection]
      expect(selection[:subjects]).to eq(count: 4, first: [letters(120), "#{letters(120)}...", "u"])
      expect(selection[:tests][:count]).to eq(4)
      expect(selection[:sources][:first].size).to eq(3)
      expect(selection).to include(config: "#{letters(120)}...", digest: "f" * 16)
    end

    it "keeps a path and subject of exactly 200 characters and clips 201" do
      with_findings(finding_with(path: letters(200), subject: letters(201)))
      shown = payload_for(survivor_report)[:findings][:shown].first
      expect(shown).to include(path: letters(200), subject: "#{letters(200)}...")
      with_findings(finding_with(path: letters(201), subject: letters(200)))
      shown = payload_for(survivor_report)[:findings][:shown].first
      expect(shown).to include(path: "#{letters(200)}...", subject: letters(200))
    end

    it "keeps snippets of exactly 200 characters and clips 201" do
      with_findings(finding_with(original: letters(200), replacement: letters(201)))
      shown = payload_for(survivor_report)[:findings][:shown].first
      expect(shown).to include(original: letters(200), replacement: "#{letters(200)}...")
    end

    it "shows at most three warnings of at most 160 characters" do
      warnings = [letters(160), letters(161), "y", "z"]
      expect(payload_for(report_of(result_for(:killed), warnings: warnings))[:warnings]).to eq(
        [letters(160), letters(160), "y"]
      )
    end
  end

  describe "the full report pointer" do
    it "is included up to 400 bytes, left out above that, and left out when there is no report" do
      expect(payload_for(survivor_report, json_report: "j" * 400)[:next]).to include(fullReport: "j" * 400)
      expect(payload_for(survivor_report, json_report: "j" * 401)[:next]).not_to have_key(:fullReport)
      expect(payload_for(survivor_report, json_report: nil)[:next]).not_to have_key(:fullReport)
    end
  end

  describe "the failure payload" do
    it "keeps 500 characters of the message and points at the help" do
      payload = described_class.failure("m" * 600, 2)
      expect(payload[:message]).to eq("m" * 500)
      expect(payload[:next]).to eq(help: "saboteur help run")
      expect(described_class.failure("short", 3)).to include(message: "short", verdict: "tool_failure", status: "error")
    end
  end

  describe "the budget" do
    let(:report) do
      report_of(*Array.new(5) { |index| result_for(:survived, replacement: "r#{index}") },
                warnings: ["careful"])
    end
    let(:long_text) { { original: letters(150), replacement: letters(150) } }

    def minimal_size
      described_class.render(described_class.send(:minimal, report, provenance_with)).bytesize
    end

    def size_of(shown, snippet_limit)
      text = described_class.render(described_class::Summary.build(report, provenance_with, shown, snippet_limit))
      text.bytesize
    end

    before do
      with_findings(*Array.new(5) { |index| finding_with(digest: format("%016d", index), **long_text) })
    end

    it "accepts a payload that is exactly the budget" do
      stub_const("Saboteur::Reporter::Agent::BYTE_BUDGET", size_of(3, 200))
      expect(payload_for(report)[:findings][:shown].size).to eq(3)
      expect(payload_for(report)[:findings][:shown].first[:original]).to eq(letters(150))
    end

    it "shrinks the snippets before it drops findings" do
      stub_const("Saboteur::Reporter::Agent::BYTE_BUDGET", size_of(3, 80))
      shown = payload_for(report)[:findings][:shown]
      expect(shown.size).to eq(3)
      expect(shown.first[:original]).to eq("#{letters(80)}...")
    end

    it "drops the snippets entirely before it drops findings" do
      stub_const("Saboteur::Reporter::Agent::BYTE_BUDGET", size_of(3, 0))
      shown = payload_for(report)[:findings][:shown]
      expect(shown.size).to eq(3)
      expect(shown.first).to include(original: "", replacement: "")
    end

    it "drops findings one at a time" do
      stub_const("Saboteur::Reporter::Agent::BYTE_BUDGET", size_of(2, 0))
      expect(payload_for(report)[:findings]).to include(survivors: 5, omitted: 3)
      expect(payload_for(report)[:findings][:shown].size).to eq(2)
    end

    it "keeps the payload without findings when that is what fits" do
      stub_const("Saboteur::Reporter::Agent::BYTE_BUDGET", size_of(0, 0))
      payload = payload_for(report)
      expect(payload[:findings]).to include(shown: [], omitted: 5)
      expect(payload[:next]).to include(:rerun)
      expect(payload[:warnings]).to eq(["careful"])
    end

    it "falls back to the minimal payload when even that does not fit" do
      stub_const("Saboteur::Reporter::Agent::BYTE_BUDGET", minimal_size)
      payload = payload_for(report)
      expect(payload[:findings][:shown]).to eq([])
      expect(payload).to include(warnings: [], next: {})
      expect(payload[:provenance].keys).to eq(%i[seed workingTree mode])
      expect(payload).to include(verdict: "survivors", exitCode: 1)
    end

    it "returns four fixed keys when even the minimal payload does not fit" do
      stub_const("Saboteur::Reporter::Agent::BYTE_BUDGET", 10)
      expect(payload_for(report)).to eq(version: 1, status: "complete", verdict: "survivors", exitCode: 1,
                                        truncated: true)
    end

    it "keeps a huge valid seed inside the budget on the normal and the minimal path" do
      huge = 10**9000
      expect(described_class.render(payload_for(report, seed: huge)).bytesize).to be <= 8192
      stub_const("Saboteur::Reporter::Agent::BYTE_BUDGET", minimal_size)
      expect(described_class.render(payload_for(report, seed: huge)).bytesize).to be <= minimal_size
    end

    it "keeps a short seed as a number and clips a seed of 21 digits" do
      expect(payload_for(report, seed: 10**19)[:provenance][:seed]).to eq(10**19)
      expect(payload_for(report, seed: 10**20)[:provenance][:seed]).to be_a(String)
    end

    it "reduces the reasons in the minimal payload to a code and a count" do
      stub_const("Saboteur::Reporter::Agent::BYTE_BUDGET", minimal_size + 100)
      payload = payload_for(report_of(result_for(:killed), result_for(:error, replacement: "<")))
      expect(payload[:incomplete]).to eq([{ reason: "errors", count: 1 }])
    end
  end
end

RSpec.describe Saboteur::Reporter::Agent::Commands do
  def provenance_with(**changes)
    Saboteur::Reporter::Agent::Provenance.new(
      ref: nil, seed: 7, head: "abc", working_tree: "clean", changed_files: 0, mode: "full", json_report: nil,
      subjects: [], tests: [], sources: [], config_path: nil, digest: nil, cache: true,
      incremental: false, settings: {}, **changes
    )
  end

  it "does not carry the run's own digest into a replay command" do
    provenance = provenance_with(digest: "a" * 16)
    expect(described_class.replay(provenance, "b" * 16)).to eq("saboteur run --id #{'b' * 16} --seed 7")
    expect(described_class.rerun(provenance)).to eq("saboteur run --agent --id #{'a' * 16} --seed 7")
  end

  it "carries the command line settings into the rerun command and the selection" do
    settings = { reeval: "a:b", integration: "rspec", jobs: 3, timeout_factor: 2.5, json_report: "j.json",
                 html_report: "h.html" }
    expect(described_class.rerun(provenance_with(settings: settings))).to eq(
      "saboteur run --agent --reeval a:b --integration rspec --jobs 3 --timeout-factor 2.5 " \
      "--json j.json --html h.html --seed 7"
    )
  end

  it "carries a shard into rerun, but never into a replay command" do
    provenance = provenance_with(settings: { shard: "2/4", jobs: 4 })
    expect(described_class.rerun(provenance)).to eq("saboteur run --agent --jobs 4 --shard 2/4 --seed 7")
    expect(described_class.replay(provenance, "b" * 16)).to eq("saboteur run --id #{'b' * 16} --jobs 4 --seed 7")
  end

  it "joins array-valued settings with commas" do
    settings = { operators: %w[range comparison], exclude_operators: ["comparison"] }
    expect(described_class.rerun(provenance_with(settings: settings))).to eq(
      "saboteur run --agent --operators range,comparison --exclude-operators comparison --seed 7"
    )
  end

  it "leaves out --since without a ref and --config without a config path" do
    expect(described_class.rerun(provenance_with)).to eq("saboteur run --agent --seed 7")
  end

  it "allows a command of exactly 1024 bytes and leaves out one byte more" do
    base = described_class.rerun(provenance_with(ref: "x")).bytesize
    exact = described_class.rerun(provenance_with(ref: "x" * (1 + 1024 - base)))
    expect(exact.bytesize).to eq(1024)
    expect(described_class.rerun(provenance_with(ref: "x" * (2 + 1024 - base)))).to be_nil
  end
end
