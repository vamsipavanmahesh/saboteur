# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "saboteur/baseline/workflow"

RSpec.describe Saboteur::Baseline::Workflow do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end
  let(:config) { Saboteur::Config.new({}, root: @root) }
  let(:workflow) { described_class.new(config: config) }
  let(:document) do
    file = File.join(@root, "probe.rb")
    File.write(file, "class Probe; def value; 1; end; end")
    subject = Saboteur::SubjectFinder.new.call(file).subjects.first
    mutation = Saboteur::MutationSource::Builtin.new.mutations_for(subject).first
    text = subject.apply(mutation.edits)
    capture = Saboteur::Baseline::RunEvidence.new(config: config)
    capture.plan([subject], [[[mutation, text]]])
    result = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :survived, mutated_source: text)
    capture.finish(results: [result], stable_suite: true, skipped_subjects: {}, generation_events: [], omissions: [])
  end

  def stub_run
    report = instance_double(Saboteur::Report, run_evidence: document)
    engine = engine_double(call: report)
    allow(Saboteur::Engine).to receive(:new).and_return(engine)
  end

  def review(path)
    record = JSON.parse(File.read(path))
    record.fetch("document").fetch("accepted").each { |entry| entry["reason"] = "reviewed" }
    File.write(path, JSON.generate(record))
    record
  end

  it "refuses an existing proposal or unreviewed destination before running the engine" do
    stub_run
    proposal = File.join(@root, "proposal.json")
    File.write(proposal, "{}")
    expect { workflow.propose(proposal: proposal, destination: File.join(@root, "b.json")) }
      .to raise_error(Saboteur::ConfigError, "baseline output exists: #{proposal}")
    File.delete(proposal)
    destination = File.join(@root, "baseline.json")
    File.write(destination, "{}")
    expect { workflow.propose(proposal: proposal, destination: destination) }
      .to raise_error(Saboteur::ConfigError, "baseline destination exists")
    expect(Saboteur::Engine).not_to have_received(:new)
  end

  it "proposes bound immutable producer evidence and accepts it only once" do
    stub_run
    proposal = File.join(@root, "proposal.json")
    destination = File.join(@root, "baseline.json")
    value = workflow.propose(proposal: proposal, destination: destination)
    expect(value).to eq("state" => "proposal", "proposal" => proposal, "destination" => destination,
                        "survivors" => 1, "candidates" => 1)
    record = review(proposal)
    expect(record.fetch("execution")).to eq(JSON.parse(JSON.generate(document)))
    expect(workflow.accept(proposal: proposal, destination: destination))
      .to eq("state" => "accepted", "destination" => destination)
    expect { workflow.accept(proposal: proposal, destination: destination) }.to raise_error(Saboteur::ConfigError)
  end

  it "requires full producer evidence even when a legacy local record otherwise validates" do
    destination = File.join(@root, "baseline.json")
    proposal = File.join(@root, "proposal.json")
    manifest = Saboteur::Baseline::Evidence.new(document).manifest
    directory = File.join(@root, ".saboteur", "baseline-evidence")
    legacy = Saboteur::Baseline::Acceptance.new(directory: directory, protected_paths: [], verify: ->(_) { true })
    legacy.propose(document: manifest, proposal: proposal, destination: destination)
    review(proposal)
    expect { workflow.accept(proposal: proposal, destination: destination) }
      .to raise_error(Saboteur::ConfigError, /execution evidence missing/)
  end

  it "rejects a mismatched manifest even when the producer evidence itself is complete" do
    captured = Saboteur::Baseline::Evidence.new(document)
    manifest = captured.manifest
    manifest["metadata"]["subjects"] = [["other.rb", "Other#m"]]
    store = Saboteur::Baseline::Acceptance.new(directory: File.join(@root, ".saboteur", "baseline-evidence"),
                                               protected_paths: [], verify: ->(_) { true }, require_evidence: true)
    expect do
      store.propose(document: manifest, evidence: captured.document,
                    proposal: File.join(@root, "p.json"), destination: File.join(@root, "b.json"))
    end.to raise_error(Saboteur::ConfigError, /execution evidence differs/)
  end

  it "adds the score comparison to a check payload only when an epsilon is given" do
    stub_run
    path = File.join(@root, "baseline.json")
    File.write(path, JSON.generate(Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")))
    expect(workflow.check(path: path)).not_to have_key("score")
    payload = workflow.check(path: path, epsilon: 2.5)
    expect(payload.fetch("score")).to eq("baseline" => 0.0, "current" => 0.0, "drop" => 0.0, "epsilon" => 2.5,
                                         "exceeded" => false, "baseline_detected" => 0, "baseline_scored" => 1,
                                         "current_detected" => 0, "current_scored" => 1)
    expect(payload.fetch("state")).to eq("clean")
  end

  it "preserves exact incomplete and incompatible check payloads without accepting invalid complete claims" do
    manifest = Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")
    path = File.join(@root, "baseline.json")
    File.write(path, JSON.generate(manifest))
    incomplete = document.merge("complete" => false, "proposable" => false,
                                "issues" => ["missing_result"], "blockers" => ["missing_result"])
    report = instance_double(Saboteur::Report, run_evidence: incomplete)
    allow(Saboteur::Engine).to receive(:new).and_return(engine_double(call: report))
    payload = workflow.check(path: path)
    expect(payload.fetch("state")).to eq("incomplete")
    expect(payload.fetch("exit_code")).to eq(3)
    expect(payload.fetch("issues")).to eq(["missing_result"])
    expect(payload.fetch("categories").fetch("accepted").size).to eq(1)
    malformed = document.merge("complete" => true, "omissions" => [{}])
    allow(report).to receive(:run_evidence).and_return(malformed)
    expect { workflow.check(path: path) }.to raise_error(Saboteur::ConfigError, /omitted/)
  end

  it "names the missing baseline file and the command that creates it" do
    path = File.join(@root, "baseline.json")
    expect { workflow.check(path: path) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to include("baseline file #{path} does not exist",
                                       "saboteur baseline propose --baseline #{path}")
    }
  end

  it "rejects oversized or corrupt baseline snapshots before execution" do
    path = File.join(@root, "baseline.json")
    File.write(path, "not json")
    expect { workflow.check(path: path) }.to raise_error(Saboteur::ConfigError, /baseline file/)
    manifest = Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")
    manifest = JSON.parse(JSON.generate(manifest))
    manifest["metadata"]["snapshot"]["digest"] = "a" * 64
    File.write(path, JSON.generate(manifest))
    expect { workflow.check(path: path) }.to raise_error(Saboteur::ConfigError, /fingerprint/)
    valid = Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")
    bytes = JSON.generate(valid)
    File.write(path, bytes)
    stub_const("Saboteur::Baseline::Acceptance::MAX_BYTES", bytes.bytesize)
    expect(workflow.send(:load_manifest, path).to_h).to eq(JSON.parse(bytes))
    stub_const("Saboteur::Baseline::Acceptance::MAX_BYTES", 3)
    File.write(path, "1234")
    expect { workflow.check(path: path) }.to raise_error(Saboteur::ConfigError, /too large/)
  end

  it "loads a manifest naming non-ASCII subjects under a non-UTF-8 locale" do
    path = File.join(@root, "baseline.json")
    manifest = JSON.parse(JSON.generate(Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")))
    manifest["candidates"].first["kill_cause"] = "caf\u00E9"
    File.write(path, JSON.generate(manifest))
    allow(File).to receive(:read).and_wrap_original do |original, *args|
      original.call(*args).force_encoding(Encoding::US_ASCII)
    end
    loaded = workflow.send(:load_manifest, path)
    expect(loaded.to_h.fetch("candidates").first.fetch("kill_cause")).to eq("caf\u00E9")
  end

  it "carries external declared evidence paths into acceptance verification" do
    document
    Dir.mktmpdir do |outside|
      extra = File.join(outside, "external.json")
      File.write(extra, "initial")
      # Engine extra_files, rather than data globs, permits external paths.
      snapshot = Saboteur::Engine::RunFingerprint.new(config: config,
                                                      extra_files: [{
                                                        path: extra, required: false
                                                      }]).snapshot
      store = workflow.send(:store, snapshot.to_h)
      metadata = { "snapshot" => snapshot.to_h }
      expect(store.instance_variable_get(:@verify).call(metadata)).to be(true)
      File.write(extra, "changed")
      expect { store.instance_variable_get(:@verify).call(metadata) }
        .to raise_error(Saboteur::ConfigError, /baseline inputs changed or unverified: external:.*changed/)
    end
  end

  it "protects input aliases at proposal and acceptance even when artifacts use innocuous extensions" do
    stub_run
    source = File.join(@root, "probe.rb")
    alias_path = File.join(@root, "alias.json")
    File.link(source, alias_path)
    # An existing alias is refused before the run; Acceptance still rejects input aliases on write.
    expect { workflow.propose(proposal: alias_path, destination: File.join(@root, "b.json")) }
      .to raise_error(Saboteur::ConfigError, "baseline output exists: #{alias_path}")
    expect { workflow.accept(proposal: File.join(@root, "p.json"), destination: source) }
      .to raise_error(Saboteur::ConfigError, /overlaps/)
  end

  it "passes fresh capture and artifact options exactly into a proposal and acceptance" do
    stub_run
    store = instance_double(Saboteur::Baseline::Acceptance)
    allow(workflow).to receive(:store).and_return(store)
    proposal = File.join(@root, "p.json")
    destination = File.join(@root, "b.json")
    File.write(destination, "reviewed")
    previous = Digest::SHA256.file(destination).hexdigest
    expect(store).to receive(:propose).with(document: anything, evidence: document, proposal: proposal,
                                            destination: destination, previous: previous)
    workflow.propose(proposal: proposal, destination: destination, previous: previous)
    expect(Saboteur::Engine).to have_received(:new).with(config, err: $stderr, capture_evidence: true)
    expect(store).to receive(:accept).with(proposal: proposal, destination: destination, previous: previous)
                                     .and_return(destination)
    workflow.accept(proposal: proposal, destination: destination, previous: previous)
  end

  it "rejects both output positions under explicitly declared extra fixture patterns" do
    extra_config = Saboteur::Config.new({ "fingerprint_extra" => ["inputs/**/*"] }, root: @root)
    extra_workflow = described_class.new(config: extra_config)
    input = File.join(@root, "inputs", "data.json")
    expect { extra_workflow.propose(proposal: File.join(@root, "p.json"), destination: input) }
      .to raise_error(Saboteur::ConfigError, /overlaps/)
    expect { extra_workflow.accept(proposal: input, destination: File.join(@root, "b.json")) }
      .to raise_error(Saboteur::ConfigError, /overlaps/)
  end

  it "protects the captured inventory even when an input vanishes after capture" do
    document
    snapshot = document.fetch("snapshot")
    source = File.join(@root, "probe.rb")
    File.unlink(source)
    protected = workflow.send(:store, snapshot).instance_variable_get(:@protected)
    expect(protected).to include(source)
  end

  it "refuses a baseline replaced after parsing even before the run fingerprint begins" do
    manifest = Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")
    path = File.join(@root, "b.json")
    File.write(path, JSON.generate(manifest))
    report = instance_double(Saboteur::Report, run_evidence: document)
    allow(Saboteur::Engine).to receive(:new) do
      File.write(path, JSON.generate(manifest).concat(" "))
      engine_double(call: report)
    end
    expect { workflow.check(path: path) }.to raise_error(Saboteur::ConfigError, /changed during check/)
  end

  it "does not publish a proposal from an incomplete run even with no survivors" do
    evidence = document.merge("proposable" => false, "candidates" => [])
    report = instance_double(Saboteur::Report, run_evidence: evidence, results: [])
    allow(Saboteur::Engine).to receive(:new).and_return(engine_double(call: report))
    expect { workflow.propose(proposal: File.join(@root, "p.json"), destination: File.join(@root, "b.json")) }
      .to raise_error(Saboteur::Error, /needs a proposable run/)
    expect(File.exist?(File.join(@root, "p.json"))).to be(false)
  end

  it "names the subject, operator and skip reason in an unexecuted blocker" do
    file = File.join(@root, "probe.rb")
    File.write(file, "class Probe; def value; 1; end; end")
    subject = Saboteur::SubjectFinder.new.call(file).subjects.first
    mutation = Saboteur::MutationSource::Builtin.new.mutations_for(subject).first
    result = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :skipped,
                                        mutated_source: "1", reason: "no coverage")
    id = Saboteur::Baseline::Identity.new(subject: subject, mutation: mutation, root: @root).entry.fetch("id")
    evidence = document.merge("proposable" => false, "blockers" => ["unexecuted:#{id}:skipped", "inputs_unverified"])
    report = instance_double(Saboteur::Report, run_evidence: evidence, results: [result])
    allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
    err = StringIO.new
    flow = described_class.new(config: config, err: err)
    expect { flow.propose(proposal: File.join(@root, "p.json"), destination: File.join(@root, "b.json")) }
      .to raise_error(Saboteur::Error, /needs a proposable run/)
    expect(err.string).to include("unexecuted:#{id}:skipped (#{subject.id} #{mutation.operator} - no coverage)")
    expect(err.string).to include("saboteur: baseline proposal blocker: inputs_unverified\n")
    expect(err.string).to include("cover the skipped code with specs or narrow include, then propose again")
  end

  it "leaves lookalike blockers and reasonless skips undecorated" do
    file = File.join(@root, "probe.rb")
    File.write(file, "class Probe; def value; 1; end; end")
    subject = Saboteur::SubjectFinder.new.call(file).subjects.first
    mutation = Saboteur::MutationSource::Builtin.new.mutations_for(subject).first
    result = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :skipped, mutated_source: "1")
    id = Saboteur::Baseline::Identity.new(subject: subject, mutation: mutation, root: @root).entry.fetch("id")
    blockers = ["x-unexecuted:#{id}:skipped", "unexecuted:#{id}:skipped!", "unexecuted:#{id}:",
                "unexecuted:#{id}:skipped"]
    evidence = document.merge("proposable" => false, "blockers" => blockers)
    report = instance_double(Saboteur::Report, run_evidence: evidence, results: [result])
    allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
    err = StringIO.new
    flow = described_class.new(config: config, err: err)
    expect { flow.propose(proposal: File.join(@root, "p.json"), destination: File.join(@root, "b.json")) }
      .to raise_error(Saboteur::Error)
    expect(err.string.lines.grep(/blocker:/).map { |l| l.split("blocker: ", 2).last }).to eq(
      ["x-unexecuted:#{id}:skipped\n", "unexecuted:#{id}:skipped!\n",
       "unexecuted:#{id}:\n",
       "unexecuted:#{id}:skipped (#{subject.id} #{mutation.operator})\n"]
    )
    expect(err.string).to include("cover the skipped code with specs or narrow include, then propose again")
  end

  it "refuses a missing or changed previous destination before running the engine" do
    stub_run
    destination = File.join(@root, "baseline.json")
    proposal = File.join(@root, "proposal.json")
    expect { workflow.propose(proposal: proposal, destination: destination, previous: "a" * 64) }
      .to raise_error(Saboteur::ConfigError, "baseline previous destination changed")
    File.write(destination, "reviewed")
    expect { workflow.propose(proposal: proposal, destination: destination, previous: "a" * 64) }
      .to raise_error(Saboteur::ConfigError, "baseline previous destination changed")
    expect(Saboteur::Engine).not_to have_received(:new)
  end

  it "lists every changed input, or says verification was incomplete" do
    change = Struct.new(:path, :reason)
    result = Struct.new(:unchanged, :changes)
    expect(workflow.send(:raise_unless_unchanged, result.new(true, []))).to be(true)
    expect do
      workflow.send(:raise_unless_unchanged,
                    result.new(false, [change.new("a.rb", "changed"), change.new("b.rb", "missing")]))
    end
      .to raise_error(Saboteur::ConfigError, "baseline inputs changed or unverified: a.rb changed, b.rb missing")
    expect { workflow.send(:raise_unless_unchanged, result.new(false, [])) }
      .to raise_error(Saboteur::ConfigError, "baseline inputs changed or unverified: verification incomplete")
  end

  it "rejects stale inputs or editable execution history before publishing" do
    stub_run
    proposal = File.join(@root, "proposal.json")
    destination = File.join(@root, "baseline.json")
    workflow.propose(proposal: proposal, destination: destination)
    record = review(proposal)
    record.fetch("execution")["generation_events"] = []
    record.fetch("execution")["issues"] = ["edited"]
    File.write(proposal, JSON.generate(record))
    expect { workflow.accept(proposal: proposal, destination: destination) }.to raise_error(Saboteur::ConfigError)
    record.fetch("execution")["issues"] = []
    File.write(proposal, JSON.generate(record))
    File.write(File.join(@root, "probe.rb"), "changed")
    expect { workflow.accept(proposal: proposal, destination: destination) }
      .to raise_error(Saboteur::ConfigError, /inputs/)
    expect(File.exist?(destination)).to be(false)
  end

  it "refuses nonfresh configuration and artifact paths that overlap present or future inputs" do
    [{ "since" => "main" }, { "incremental" => true }, { "threshold" => 90 }].each do |settings|
      expect { described_class.new(config: Saboteur::Config.new(settings, root: @root)) }
        .to raise_error(Saboteur::ConfigError, /fresh whole|score threshold/)
    end
    %w[lib/a.rb config/database.yml Gemfile spec/fixtures/data.json].each do |path|
      expect { workflow.propose(proposal: File.join(@root, path), destination: File.join(@root, "b.json")) }
        .to raise_error(Saboteur::ConfigError, /overlaps/)
    end
  end

  it "runs check fresh with the baseline file in the input fingerprint and returns review state" do
    manifest = Saboteur::Baseline::Evidence.new(document).manifest(reasons: "known")
    path = File.join(@root, "baseline.json")
    File.write(path, JSON.generate(manifest))
    stub_run
    expect(workflow.check(path: path).fetch("state")).to eq("clean")
    expect(Saboteur::Engine).to have_received(:new).with(config, err: $stderr, capture_evidence: true,
                                                                 evidence_files: [path])
  end

  it "publishes a proposal over soft gaps, listing them in the payload" do
    gap = "subject_skipped:probe.rb:Probe#other:no_tests"
    gapped = document.merge("complete" => false, "issues" => [gap], "gaps" => [gap], "blockers" => [])
    report = instance_double(Saboteur::Report, run_evidence: gapped)
    allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
    value = workflow.propose(proposal: File.join(@root, "p.json"), destination: File.join(@root, "b.json"))
    expect(value.fetch("state")).to eq("proposal")
    expect(value.fetch("gaps")).to eq([gap])
    record = JSON.parse(File.read(File.join(@root, "p.json")))
    expect(record.fetch("document").fetch("metadata").fetch("proposable")).to be(true)
    expect(record.fetch("document").fetch("metadata").fetch("issues")).to eq([gap])
  end

  it "checks a gapped-but-proposable run against a gapped baseline as clean" do
    gap = "subject_skipped:probe.rb:Probe#other:no_tests"
    gapped = document.merge("complete" => false, "issues" => [gap], "gaps" => [gap], "blockers" => [])
    manifest = Saboteur::Baseline::Evidence.new(gapped).manifest(reasons: "known")
    path = File.join(@root, "baseline.json")
    File.write(path, JSON.generate(manifest))
    report = instance_double(Saboteur::Report, run_evidence: gapped)
    allow(Saboteur::Engine).to receive(:new).and_return(instance_double(Saboteur::Engine, call: report))
    payload = workflow.check(path: path)
    expect(payload.fetch("state")).to eq("clean")
    expect(payload.fetch("exit_code")).to eq(0)
  end
end
