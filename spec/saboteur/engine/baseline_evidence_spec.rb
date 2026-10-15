# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine, "baseline evidence capture" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return({})
  end

  it "rejects reuse, diff and replay before target boot" do
    [{ "since" => "main" }, { "incremental" => true }].each do |settings|
      config = Saboteur::Config.new(settings)
      expect { described_class.new(config, capture_evidence: true) }.to raise_error(Saboteur::ConfigError, /fresh/)
    end
    expect do
      described_class.new(Saboteur::Config.new, capture_evidence: true, digest: "a" * 16)
    end.to raise_error(Saboteur::ConfigError, /fresh/)
  end

  it "plans every selected candidate before distribution and reconciles the fresh result" do
    Dir.mktmpdir do |directory|
      root = File.realpath(directory)
      file = File.join(root, "probe.rb")
      File.write(file, "class Probe; def value; 1; end; end")
      subject = Saboteur::SubjectFinder.new.call(file).subjects.first
      source = Saboteur::MutationSource::Builtin.new
      candidate = source.mutations_for(subject).first
      result = Saboteur::MutantResult.new(subject: subject, mutation: candidate, status: :survived,
                                          mutated_source: subject.apply(candidate.edits))
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [], all_tests: [])
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject], changed_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
      guard = instance_double(Saboteur::Engine::BaselineGuard, call: nil)
      allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(guard)
      map = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"])
      store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false, fetch: map)
      allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
      allow_any_instance_of(Saboteur::Engine::Candidates).to receive(:for)
        .and_return([[candidate, subject.apply(candidate.edits)]])
      distribution = instance_double(Saboteur::Engine::Distribution, unreached: [])
      allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
      expect(distribution).to receive(:run).and_return([result])
      allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)

      report = described_class.new(Saboteur::Config.new({}, root: root), capture_evidence: true,
                                                                         err: StringIO.new).call

      expect(report.run_evidence.fetch("complete")).to be(true)
      expect(report.run_evidence.fetch("planned").map { |entry| entry.fetch("id") })
        .to eq(report.run_evidence.fetch("candidates").map { |entry| entry.fetch("id") })
      expect(report.run_evidence.fetch("candidates").first.fetch("status")).to eq("survived")
    end
  end

  it "passes typed discovery failures through a mixed included-file engine run" do
    Dir.mktmpdir do |directory|
      root = File.realpath(directory)
      file = File.join(root, "probe.rb")
      File.write(file, "class Probe; def value; 1; end; end")
      subject = Saboteur::SubjectFinder.new.call(file).subjects.first
      source = Saboteur::MutationSource::Builtin.new
      candidate = source.mutations_for(subject).first
      result = Saboteur::MutantResult.new(subject: subject, mutation: candidate, status: :survived,
                                          mutated_source: subject.apply(candidate.edits))
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [], all_tests: [])
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      File.write(File.join(root, "broken.rb"), "class Broken; def ( ; end")
      guard = instance_double(Saboteur::Engine::BaselineGuard, call: nil)
      allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(guard)
      map = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"])
      store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false, fetch: map)
      allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
      allow_any_instance_of(Saboteur::Engine::Candidates).to receive(:for)
        .and_return([[candidate, subject.apply(candidate.edits)]])
      distribution = instance_double(Saboteur::Engine::Distribution, unreached: [])
      allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
      expect(distribution).to receive(:run).and_return([result])
      allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)

      config = Saboteur::Config.new({ "include" => ["*.rb"], "all" => true }, root: root)
      report = described_class.new(config, capture_evidence: true, err: StringIO.new).call

      expect(report.run_evidence.fetch("complete")).to be(false)
      expect(report.run_evidence.fetch("issues"))
        .to include("generation:discovery:invalid_file_syntax:broken.rb")
      expect(report.run_evidence.fetch("planned").map { |entry| entry.fetch("id") })
        .to eq(report.run_evidence.fetch("candidates").map { |entry| entry.fetch("id") })
      expect(report.run_evidence.fetch("candidates").first.fetch("status")).to eq("survived")
    end
  end

  it "captures input identity before target boot and refuses changed inputs after boot" do
    Dir.mktmpdir do |directory|
      root = File.realpath(directory)
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      boot = instance_double(Saboteur::Engine::Boot, rails: nil)
      allow(boot).to receive(:load_target) do
        File.write(File.join(root, "loaded.rb"), "new input")
        instance_double(Saboteur::Integration::RSpec)
      end
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      selection = instance_double(Saboteur::Engine::SubjectSelection, select: [], changed_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)

      report = described_class.new(Saboteur::Config.new({}, root: root), capture_evidence: true,
                                                                         err: StringIO.new).call

      expect(report.run_evidence.fetch("complete")).to be(false)
      expect(report.run_evidence.fetch("issues")).to include("inputs_unverified", "empty_candidates",
                                                             "unchanged_suite_incomplete")
    end
  end
  it "certifies the suite stable only after repeated green passes, not one (#245)" do
    [1, 2].each do |passes|
      Dir.mktmpdir do |directory|
        root = File.realpath(directory)
        file = File.join(root, "probe.rb")
        File.write(file, "class Probe; def value; 1; end; end")
        subject = Saboteur::SubjectFinder.new.call(file).subjects.first
        source = Saboteur::MutationSource::Builtin.new
        candidate = source.mutations_for(subject).first
        result = Saboteur::MutantResult.new(subject: subject, mutation: candidate, status: :survived,
                                            mutated_source: subject.apply(candidate.edits))
        allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
        integration = instance_double(Saboteur::Integration::RSpec, test_files: [], all_tests: [])
        boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
        allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
        selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject], changed_lines: nil)
        allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
        guard = instance_double(Saboteur::Engine::BaselineGuard, call: nil)
        allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(guard)
        map = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"])
        # A reusable store adds no extra pass, so full_passes is exactly the
        # configured --baseline-passes.
        store = instance_double(Saboteur::Engine::CoverageStore, reusable?: true, fetch: map)
        allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
        allow_any_instance_of(Saboteur::Engine::Candidates).to receive(:for)
          .and_return([[candidate, subject.apply(candidate.edits)]])
        distribution = instance_double(Saboteur::Engine::Distribution, unreached: [])
        allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
        allow(distribution).to receive(:run).and_return([result])
        allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)

        allow_any_instance_of(Saboteur::Baseline::RunEvidence).to receive(:finish)
          .and_wrap_original do |original, **args|
          expect(args.fetch(:stable_suite)).to be(passes >= 2)
          original.call(**args)
        end
        described_class.new(Saboteur::Config.new({ "baseline_passes" => passes }, root: root),
                            capture_evidence: true, err: StringIO.new).call
      end
    end
  end

  it "fingerprints engine-supplied evidence files and passes false for an unrun baseline" do
    Dir.mktmpdir do |directory|
      root = File.realpath(directory)
      evidence_file = File.join(root, "external-evidence.txt")
      File.write(evidence_file, "initial")
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      boot = instance_double(Saboteur::Engine::Boot, rails: nil)
      allow(boot).to receive(:load_target) do
        File.write(evidence_file, "changed")
        instance_double(Saboteur::Integration::RSpec)
      end
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      selection = instance_double(Saboteur::Engine::SubjectSelection, select: [], changed_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)

      allow_any_instance_of(Saboteur::Baseline::RunEvidence).to receive(:finish).and_wrap_original do |original, **args|
        expect(args.fetch(:stable_suite)).to be(false)
        original.call(**args)
      end
      report = described_class.new(Saboteur::Config.new({}, root: root), capture_evidence: true,
                                                                         evidence_files: [evidence_file],
                                                                         err: StringIO.new).call

      expect(report.run_evidence.fetch("complete")).to be(false)
      expect(report.run_evidence.fetch("issues")).to include("inputs_unverified", "empty_candidates",
                                                             "unchanged_suite_incomplete")
    end
  end
end
