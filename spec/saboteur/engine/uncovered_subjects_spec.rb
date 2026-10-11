# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "uncovered subjects" do
  let(:subject_under_test) { subjects_in("class Uncovered\n  def m\n    1\n  end\nend\n").first }

  [1, 2].each do |jobs|
    it "keeps uncovered subjects in the report without invoking sources (#{jobs} workers)" do
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      selection = instance_double(Saboteur::Engine::SubjectSelection,
                                  select: [subject_under_test], changed_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
      map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
      store = instance_double(Saboteur::Engine::CoverageStore, fetch: map)
      allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
      expect_any_instance_of(Saboteur::Engine::Candidates).not_to receive(:for)
      Dir.mktmpdir do |root|
        config = Saboteur::Config.new({ "jobs" => jobs, "cache_dir" => root }, root: root)
        report = described_class.new(config, err: StringIO.new).call
        expect(report.subjects).to eq([subject_under_test])
        expect(report.results).to be_empty
        expect(report.skipped_subjects).to eq(subject_under_test => "no coverage")
        expect(report.score).to be_nil
      end
    end
  end
end
