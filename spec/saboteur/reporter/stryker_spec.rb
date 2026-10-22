# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "tmpdir"

RSpec.describe Saboteur::Reporter::Stryker do
  let(:report) do
    survivor = result_for(:survived, replacement: "==", runtime: 0.01)
    survivor.ignored = "equivalent"
    report_of(result_for(:killed, runtime: 0.25, killed_by: ["t1"], covered_by: %w[t1 t2]),
              survivor,
              result_for(:timeout, replacement: "<"), result_for(:error, replacement: "<=", reason: "boom\nmore"),
              result_for(:skipped, replacement: "!=", reason: "no coverage"),
              result_for(:skipped, replacement: "!=", reason: "baseline failure"))
  end
  let(:json) { JSON.parse(JSON.generate(described_class.build(report))) }
  let(:mutants) { json.dig("files", "person.rb", "mutants") }

  it "writes schema version 2 with one entry per file, holding the full source" do
    expect(json["schemaVersion"]).to eq("2")
    expect(json["files"].keys).to eq(["person.rb"])
    expect(json.dig("files", "person.rb", "source")).to eq(ReportHelpers::PERSON)
    expect(json.dig("files", "person.rb", "language")).to eq("ruby")
  end

  it "carries the subject id on every file-section mutant, so --show can complete its ignore template (#1181)" do
    expect(mutants.map { |m| m["subject"] }).to all(eq(person_subject.id))
  end

  it "records per-worker and supervisor peak memory when the run measured it (#202)" do
    memory = { workers: [{ worker: 0, peakMb: 12.1 }, { worker: 1, peakMb: 11.0 }], supervisorPeakMb: 30.5 }
    payload = JSON.parse(JSON.generate(described_class.build(report_of(result_for(:killed), memory:))))
    expect(payload.dig("saboteur", "memory")).to eq(
      "workers" => [{ "worker" => 0, "peakMb" => 12.1 }, { "worker" => 1, "peakMb" => 11.0 }],
      "supervisorPeakMb" => 30.5
    )
  end

  it "omits the memory section when the run measured none" do
    payload = JSON.parse(JSON.generate(described_class.build(report_of(result_for(:killed)))))
    expect(payload.fetch("saboteur")).not_to have_key("memory")
  end

  it "never labels a --test-command survivor a gap kind from pseudo evidence (#305)" do
    external = result_for(:survived, covered_by: [Saboteur::Execution::ExternalRunner::PSEUDO_TEST])
    report = report_of(external, result_for(:survived, covered_by: %w[t1], replacement: "<="))
    mutants = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants")
    expect(mutants.map { |m| m["classification"] }).to eq(%w[tool_limit boundary])
  end

  it "labels survivors with their classification, and only survivors (#192)" do
    covered = result_for(:survived, covered_by: %w[t1])
    report = report_of(covered, result_for(:killed, covered_by: %w[t1]))
    mutants = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants")
    expect(mutants.map { |m| m["classification"] }).to eq(["boundary", nil])
  end

  it "builds valid JSON with multibyte source on and before the edited line (#192)" do
    source = "class Person\n  # caf\u00e9\n  def tell(msg)\n    puts \"\u00e9 \#{msg}\"\n  end\nend\n"
    dir = Dir.mktmpdir("saboteur-stryker-utf8-")
    path = File.join(dir, "person.rb")
    File.write(path, source)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    at = source.b.index("puts".b)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 4,
                                              replacement: "nil")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit], coarse: false)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits), covered_by: [])
    report = Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0,
                                  root: dir, seed: 1, operator_policy: Saboteur::Config.new({}).operator_policy)
    mutant = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants").first
    expect(mutant["classification"]).to eq("arid")
  end

  it "carries the operator policy under the saboteur key" do
    expected = JSON.parse(JSON.generate(Saboteur::Config.new({}).operator_policy))
    expect(json.dig("saboteur", "operatorPolicy")).to eq(expected)
    expect(json.fetch("saboteur")).not_to have_key("shard")
  end

  it "records shard metadata under the saboteur extension without changing the schema version" do
    shard = Saboteur::Engine::Shard.parse("2/4")
    allow(shard).to receive(:to_h).and_return(index: 2, of: 4, selected: 3, planned: 10,
                                              inventoryDigest: "a" * 64, partial: true)
    allow(shard).to receive_messages(planned_count: 10, selected_count: 3)
    allow(report).to receive(:shard).and_return(shard)
    document = JSON.parse(JSON.generate(described_class.build(report)))
    expect(document["schemaVersion"]).to eq("2")
    expect(document.dig("saboteur", "shard")).to eq(
      "index" => 2, "of" => 4, "selected" => 3, "planned" => 10,
      "inventoryDigest" => "a" * 64, "partial" => true
    )
  end

  it "maps ran-at-load and unreachable to Ignored, carrying the reason" do
    report = report_of(result_for(:ran_at_load, reason: "ran while the app loaded"),
                       result_for(:unreachable, reason: "a captured Method still calls the original"))
    mutants = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants")
    expect(mutants.map { |m| m["status"] }).to eq(%w[Ignored Ignored])
    expect(mutants.map { |m| m["statusReason"] })
      .to eq(["ran while the app loaded", "a captured Method still calls the original"])
  end

  it "maps branch skips to NoCoverage and keeps a reasonless skip Ignored" do
    report = report_of(result_for(:skipped, reason: "no coverage (branch not taken)"), result_for(:skipped))
    statuses = described_class.build(report).dig(:files, "person.rb", :mutants).map { |mutant| mutant[:status] }
    expect(statuses).to eq(%w[NoCoverage Ignored])
  end

  it "records the tests that ran as executed ids, absent when the run did not record them" do
    report = report_of(result_for(:survived, covered_by: %w[t1 t2], executed: %w[t2]),
                       result_for(:killed, covered_by: %w[t1], killed_by: %w[t1]))
    mutants = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants")
    expect(mutants.map { |m| m["coveredBy"] }).to eq([%w[0 1], ["0"]])
    expect(mutants.map { |m| m["executed"] }).to eq([["1"], nil])
  end

  it "indexes executed-only test names so executed ids resolve" do
    report = report_of(result_for(:survived, covered_by: %w[t1], executed: %w[t1 tX]))
    mutant = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants").first
    expect(mutant["coveredBy"]).to eq(["0"])
    expect(mutant["executed"]).to eq(%w[0 1])
  end

  it "indexes killed-only test names so killedBy ids resolve" do
    report = report_of(result_for(:killed, covered_by: %w[t1], killed_by: %w[t9]))
    mutant = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants").first
    expect(mutant["killedBy"]).to eq(["1"])
  end

  it "records the seed, so the run can be repeated" do
    expect(json["config"]).to eq("seed" => 1)
  end

  it "records the ref of a diff run, so the score's scope survives" do
    result = result_for(:survived)
    scope = Saboteur::Engine::DiffScope.new({ person_subject.file => Set.new([3]) })
    report = Saboteur::Report.new(results: [result], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1, diff_scope: scope,
                                  since: "HEAD~1")
    expect(JSON.parse(JSON.generate(described_class.build(report)))["config"])
      .to eq("seed" => 1, "since" => "HEAD~1")
  end

  it "omits the ref key when a diff run recorded no ref" do
    result = result_for(:survived)
    scope = Saboteur::Engine::DiffScope.new({ person_subject.file => Set.new([3]) })
    report = Saboteur::Report.new(results: [result], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1, diff_scope: scope)
    expect(JSON.parse(JSON.generate(described_class.build(report)))["config"])
      .to eq("seed" => 1)
  end

  it "omits the ref key for a whole-project run that happens to know a ref" do
    result = result_for(:survived)
    report = Saboteur::Report.new(results: [result], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1, since: "HEAD~1")
    expect(JSON.parse(JSON.generate(described_class.build(report)))["config"])
      .to eq("seed" => 1)
  end

  it "maps every saboteur status to a distinct schema status" do
    expect(mutants.map { |m| m["status"] })
      .to eq(%w[Killed Survived Timeout RuntimeError NoCoverage Ignored])
  end

  it "records 1-based positions, the replacement, tests and duration" do
    killed = mutants.first
    expect(killed["location"]).to eq("start" => { "line" => 2, "column" => 20 },
                                     "end" => { "line" => 2, "column" => 22 })
    expect(killed.values_at("mutatorName", "replacement", "killedBy", "coveredBy", "duration"))
      .to eq(["comparison", ">", ["0"], %w[0 1], 250])
    expect(killed["id"]).to match(/\A\h{16}\z/)
  end

  # A multi-edit mutant is one mutant with one text: the edits' replacements
  # join with the same " | " the findings report uses (#707).
  it "joins a multi-edit mutant's replacements with a pipe separator (#707)" do
    subject = person_subject
    source = subject.file_source
    gte = source.index(">=")
    age = source.index("18")
    edits = [
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: gte, end_byte: gte + 2, replacement: "LT"),
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: age, end_byte: age + 2, replacement: "AGE")
    ]
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits:, coarse: false)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(edits), covered_by: [])
    mutants = JSON.parse(JSON.generate(described_class.build(report_of(result)))).dig("files", "person.rb", "mutants")
    expect(mutants.first["replacement"]).to eq("LT | AGE")
  end

  it "reads the source through its own copy and leaves the subject's string encoding alone" do
    result = result_for(:killed)
    raw = result.subject.file_source.b
    allow(result.subject).to receive(:file_source).and_return(raw)
    described_class.build(report_of(result))
    expect(raw.encoding).to eq(Encoding::BINARY)
  end

  it "lists each test once under testFiles, grouped by spec file" do
    report = report_of(result_for(:killed, killed_by: ["./spec/a_spec.rb[1:1]"],
                                           covered_by: ["./spec/a_spec.rb[1:1]", "./spec/b_spec.rb[2]"]))
    json = JSON.parse(JSON.generate(described_class.build(report)))
    expect(json["testFiles"]).to eq(
      "spec/a_spec.rb" => { "tests" => [{ "id" => "0", "name" => "./spec/a_spec.rb[1:1]" }] },
      "spec/b_spec.rb" => { "tests" => [{ "id" => "1", "name" => "./spec/b_spec.rb[2]" }] }
    )
  end

  it "numbers tests by sorted name, so timing order never renames an id (#1282)" do
    a = "./spec/a_spec.rb[1:1]"
    b = "./spec/b_spec.rb[2]"
    c = "./spec/c_spec.rb[1]"
    ids = [[c, a, b], [b, c, a], [a, b, c]].map do |order|
      report = report_of(result_for(:killed, killed_by: [order.first], covered_by: order))
      json = JSON.parse(JSON.generate(described_class.build(report)))
      mutant = json.dig("files", "person.rb", "mutants").first
      [json["testFiles"], mutant["killedBy"], mutant["coveredBy"]]
    end
    expect(ids.map(&:first).uniq.size).to eq(1)
    expect(ids.first.first.values.flat_map { |entry| entry["tests"] }.to_h { |t| [t["name"], t["id"]] })
      .to eq(a => "0", b => "1", c => "2")
    expect(ids.map { |_, killed_by, _| killed_by }).to eq([["2"], ["1"], ["0"]])
  end

  it "reports the score with its assertion and crash shares, with and without whole-body mutants" do
    report = report_of(result_for(:killed, coarse: true, kill_cause: "TypeError"),
                       result_for(:killed, replacement: "<", kill_cause: "assertion"))
    scores = described_class.build(report).dig(:saboteur, :scores)
    expect(scores[:all]).to include(score: 1.0, assertionShare: 0.5, crashShare: 0.5)
    expect(scores[:withoutWholeBodyMutants]).to include(tested: 1, assertionShare: 1.0, crashShare: 0.0)
  end

  it "says what killed a killed mutant: an assertion or a crash" do
    report = report_of(result_for(:killed, kill_cause: "assertion"), result_for(:killed, kill_cause: "TypeError"))
    reasons = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants")
                  .map { |m| m["statusReason"] }
    expect(reasons).to eq(["assertion", "crash: TypeError"])
  end

  it "maps a resource-limit stop to RuntimeError with its reason" do
    report = report_of(result_for(:resource_limit, reason: "process tree grew by 3000 MB (limit 2048 MB)"))
    mutant = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants").first
    expect(mutant.values_at("status", "statusReason"))
      .to eq(["RuntimeError", "resource limit: process tree grew by 3000 MB (limit 2048 MB)"])
  end

  it "keeps ignored survivors as Survived with the reason, and full error reasons" do
    expect(mutants[1]["statusReason"]).to eq("ignored: equivalent")
    expect(mutants[3]["statusReason"]).to eq("boom\nmore")
  end

  it "names the triage state in statusReason (#155)" do
    accepted = result_for(:survived)
    accepted.ignored = "equivalent"
    accepted.triage_state = "accepted_equivalent"
    wont_fix = result_for(:survived, replacement: "<")
    wont_fix.ignored = "legacy"
    wont_fix.triage_state = "wont_fix"
    todo = result_for(:survived, replacement: "==")
    todo.triage_state = "todo"
    todo.triage_reason = "fix in the next sprint"
    mutants = JSON.parse(JSON.generate(described_class.build(report_of(accepted, wont_fix, todo))))
                  .dig("files", "person.rb", "mutants")
    # statusReason is a public contract: every ignored state keeps the
    # "ignored: " prefix consumers classify by (#304 CI). accepted_equivalent
    # is byte-identical to a plain ignore; only wont_fix adds a suffix.
    expect(mutants.map { |m| [m["status"], m["statusReason"]] }).to eq([
                                                                         ["Survived", "ignored: equivalent"],
                                                                         ["Survived", "ignored: legacy (wont_fix)"],
                                                                         ["Survived", "todo: fix in the next sprint"]
                                                                       ])
  end

  # A rejected kill's reason carries the child's full failure detail: the
  # JSON report must keep every line, or CI shows "expected: 0" with no
  # context again (#296).
  it "keeps every line of a multiline error reason in statusReason (#296)" do
    detail = "killing test t1 also fails with the method unchanged: NameError: uninitialized constant X\n" \
             "./spec/x_spec.rb:4:in `block'\n./spec/x_spec.rb:9:in `block'"
    report = report_of(result_for(:error, reason: detail))
    mutant = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants").first
    expect(mutant["statusReason"]).to eq(detail)
  end

  it "omits statusReason when the surviving reason is blank (#296)" do
    report = report_of(result_for(:survived, reason: "   "))
    mutant = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants").first
    expect(mutant["statusReason"]).to be_nil
  end

  it "carries the bounded findings a code-review surface annotates from" do
    findings = json.fetch("saboteur").fetch("findings")
    expect(findings["version"]).to eq(1)
    expect(findings["survivors"]).to eq([])
    expect(findings["accepted"].map { |finding| finding["reason"] }).to eq(["equivalent"])
  end

  it "writes the file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out", "report.json")
      described_class.new(path).call(report)
      expect(JSON.parse(File.read(path))["schemaVersion"]).to eq("2")
    end
  end
  it "records the run's exit cause when the CLI supplies one" do
    document = described_class.build(report, exit_cause: "errorMajority")
    expect(document.fetch(:saboteur).fetch(:exitCause)).to eq("errorMajority")
  end

  it "omits the exit cause when none is supplied" do
    document = described_class.build(report)
    expect(document.fetch(:saboteur)).not_to have_key(:exitCause)
  end

  describe "schema keys the #513 dogfood found unpinned" do
    it "emits the score thresholds" do
      expect(json["thresholds"]).to eq("high" => 80, "low" => 60)
    end

    it "emits the framework identity" do
      expect(json["framework"]).to eq("name" => "saboteur", "version" => Saboteur::VERSION)
    end

    it "omits the config key when the run recorded no seed" do
      no_seed = Saboteur::Report.new(results: report.results, subjects: report.subjects,
                                     wall_time: 1.25, root: report.root,
                                     operator_policy: report.operator_policy)
      expect(JSON.parse(JSON.generate(described_class.build(no_seed)))).not_to have_key("config")
    end

    it "audits inline suppressions with root-relative files under the saboteur key" do
      entry = { file: File.join(report.root, "person.rb"), line: 2, subject: "Person#adult?",
                operator: "comparison", digest: "a" * 16, reason: "covered elsewhere" }
      audited = Saboteur::Report.new(results: report.results, subjects: report.subjects,
                                     wall_time: 1.25, root: report.root, seed: 1,
                                     operator_policy: report.operator_policy,
                                     inline_suppressions: [entry])
      payload = JSON.parse(JSON.generate(described_class.build(audited)))
      expect(payload.dig("saboteur", "inlineSuppressions")).to eq(
        [entry.merge(file: "person.rb").transform_keys(&:to_s)]
      )
    end

    it "records the per-gate breakdown when the CLI supplies one (#473)" do
      breakdown = [{ pattern: "app/payments/**/*", minScore: 95, mutants: 2, tested: 2, score: 50.0,
                     passed: false, failingSubjects: 1, files: ["app/payments/charge.rb"] }]
      document = JSON.parse(JSON.generate(described_class.build(report, score_gates: breakdown)))
      expect(document.fetch("saboteur").fetch("scoreGates")).to eq(JSON.parse(JSON.generate(breakdown)))
    end

    it "omits the per-gate breakdown when no score gates are configured" do
      document = JSON.parse(JSON.generate(described_class.build(report)))
      expect(document.fetch("saboteur")).not_to have_key("scoreGates")
    end

    it "passes the CLI's exit cause through the instance call into the written file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out", "report.json")
        described_class.new(path).call(report, exit_cause: "errorMajority")
        expect(JSON.parse(File.read(path)).dig("saboteur", "exitCause")).to eq("errorMajority")
      end
    end
  end
end
