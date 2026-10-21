# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "uncovered subjects" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
  end

  let(:subject_under_test) { subjects_in("class Uncovered\n  def m\n    1\n  end\nend\n").first }

  [1, 2].each do |jobs|
    it "keeps uncovered subjects in the report without invoking sources (#{jobs} workers)" do
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      baseline = instance_double(Saboteur::Engine::BaselineGuard, call: nil, completed_passes: 2)
      allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
      rails = instance_double(Saboteur::Frameworks::Rails)
      expect(rails).not_to receive(:prepare_workers)
      expect(rails).not_to receive(:start_worker)
      # No runnable work still reaches the Engine.call boundary, which
      # releases whatever the boot already snapshotted.
      expect(rails).to receive(:cleanup_workers)
      expect(Saboteur::Engine::Distribution).not_to receive(:new)
      expect(Saboteur::Execution::WorkerPool).not_to receive(:new)
      expect(Saboteur::Execution::ForkReadiness).not_to receive(:prepare_heap)
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: rails)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      selection = instance_double(Saboteur::Engine::SubjectSelection,
                                  select: [subject_under_test], behavior_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
      map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
      store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false, fetch: map)
      allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
      expect_any_instance_of(Saboteur::Engine::Candidates).not_to receive(:for)
      Dir.mktmpdir do |root|
        config = Saboteur::Config.new({ "jobs" => jobs, "cache_dir" => root }, root: root)
        engine = described_class.new(config, err: StringIO.new)
        engine.hooks.register(:worker_start) { raise "worker should not start" }
        report = engine.call
        expect(report.subjects).to eq([subject_under_test])
        expect(report.results).to be_empty
        expect(report.skipped_subjects).to eq(subject_under_test => "no tests")
        expect(report.score).to be_nil
        expect(report.review?).to be(false)
      end
    end
  end
end
