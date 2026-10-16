# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "replay wiring" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return({})
  end

  let(:config) { Saboteur::Config.new({ "incremental" => true, "all" => true }) }
  let(:subject) { person_subject }
  let(:mutation) { comparison_mutation }
  let(:digest) { mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source) }
  let(:candidate) { [mutation, subject.apply(mutation.edits)] }
  let(:selection) { instance_double(Saboteur::Engine::SubjectSelection, select: [subject], changed_lines: nil) }

  def engine(id = nil)
    described_class.new(config, err: StringIO.new, digest: id)
  end

  before do
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  it "resolves one real candidate and bypasses caps and cache" do
    candidates = instance_double(Saboteur::Engine::Candidates, for: [candidate])
    allow(Saboteur::Engine::Candidates).to receive(:new).and_return(candidates)
    run = engine(digest)
    expect(run.send(:select_subjects, [])).to eq([[subject], nil])
    expect(run.send(:candidate_lists, [subject], nil, nil)).to eq([[candidate]])
    expect(run.send(:result_cache)).to be_nil
  end

  it "keeps ordinary selection and its incremental cache without a replay" do
    run = engine
    expect(run.send(:select_subjects, [])).to eq([[subject], nil])
    expect(run.send(:result_cache)).to be_a(Saboteur::Engine::ResultCache)
    candidates = instance_double(Saboteur::Engine::CandidateSelection, for: [candidate], skipped_subjects: {},
                                                                       unscoped_digests: {})
    allow(Saboteur::Engine::CandidateSelection).to receive(:new).and_return(candidates)
    expect(run.send(:candidate_lists, [subject], nil, nil)).to eq([[candidate]])
  end

  it "keeps normal changed-line scope and passes it through digest resolution" do
    lines = { subject.file => Set[999] }
    allow(selection).to receive(:changed_lines).and_return(lines)
    expect(engine.send(:select_subjects, []).last).to be_a(Saboteur::Engine::DiffScope)
    candidates = instance_double(Saboteur::Engine::Candidates, for: [candidate])
    allow(Saboteur::Engine::Candidates).to receive(:new).and_return(candidates)
    expect { engine(digest).send(:select_subjects, []) }.to raise_error(Saboteur::ConfigError, /not found/)
  end

  it "loads ignores in ordinary mode but not in replay mode" do
    boot = instance_double(Saboteur::Engine::Boot,
                           load_target: instance_double(Saboteur::Integration::RSpec, test_files: []), rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    allow(selection).to receive(:select).and_return([])
    expect(Saboteur::IgnoreList).to receive(:load).with(config.path("ignore_file")).and_return(Saboteur::IgnoreList.new([]))
    expect(engine.call.results).to eq([])
    run = engine(digest)
    allow(run).to receive(:select_subjects).and_return([[], nil])
    expect(Saboteur::IgnoreList).not_to receive(:load)
    expect(run.call.results).to eq([])
  end
end

RSpec.describe Saboteur::CLI, "replay option and output" do
  it "passes a parsed digest only for replay and renders the real reporter" do
    [nil, "a" * 16].each do |digest|
      out = StringIO.new
      err = StringIO.new
      result = result_for(:killed)
      report = report_of(result)
      config = Saboteur::Config.new({ "json_report" => nil })
      allow(Saboteur::Config).to receive(:load).and_return(config)
      arguments = { err: err, verbose: false }
      arguments[:digest] = digest if digest
      expect(Saboteur::Engine).to receive(:new).with(config, **arguments)
                                               .and_return(instance_double(Saboteur::Engine, call: report))
      argv = digest ? ["run", "--id", digest] : ["run"]
      expect(described_class.new(argv, out: out, err: err).call).to eq(0)
      if digest
        expect(out.string).to include("Replay: #{result.subject.id}", result.digest, "Selected tests:")
      else
        expect(out.string).not_to include("Replay:")
      end
    end
  end
end

RSpec.describe Saboteur::Reporter::Replay do
  it "prints diff and selected test identity, or explicitly none, for every verdict" do
    out = StringIO.new
    results = %i[killed survived timeout error skipped].map { |status| result_for(status) }
    results.first.covered_by << "spec/person_spec.rb[1:2]"
    report = report_of(*results)
    described_class.new(out).call(report)
    results.each do |result|
      expect(out.string).to include("#{result.digest} (#{result.status})", result.diff(root: report.root))
    end
    expect(out.string).to include("  spec/person_spec.rb[1:2]", "  none")
    expect(out.string.scan("Selected tests:").size).to eq(5)
    expect(out.string.scan("  none").size).to eq(4)
  end
end
