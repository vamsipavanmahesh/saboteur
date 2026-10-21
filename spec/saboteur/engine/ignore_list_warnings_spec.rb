# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The ignore list's warnings (an ignored survivor that disappeared, say)
# must reach the report, or the user never hears about stale entries.
RSpec.describe Saboteur::Engine, "ignore list warnings" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
  end

  it "carries the ignore list's warnings into the report" do
    Dir.mktmpdir do |root|
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      selection = instance_double(Saboteur::Engine::SubjectSelection, select: [], behavior_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
      ignore_list = instance_double(Saboteur::IgnoreList, apply: ["ignored survivor abc is gone"])
      allow(Saboteur::IgnoreList).to receive(:load).and_return(ignore_list)
      report = described_class.new(Saboteur::Config.new({}, root: root), err: StringIO.new).call
      expect(report.warnings).to include("ignored survivor abc is gone")
      expect(ignore_list).to have_received(:apply)
        .with([], subjects: [], unscoped_digests: nil, full_run: true)
    end
  end

  # --subject, explicit file arguments, and --since all narrow what the run
  # examines without setting a diff scope; none may flip the
  # missing-subject check on, or every entry for other subjects warns.
  {
    "a --subject filter" => { "subjects" => ["K#m"] },
    "explicit file arguments" => { "include" => ["lib/models/**/*.rb"] },
    "a --since diff" => { "since" => "HEAD" }
  }.each do |label, scoped_config|
    it "passes full_run: false for #{label}" do
      Dir.mktmpdir do |root|
        # --since validates a git repo and resolves the ref
        system("git", "init", "-q", chdir: root)
        system("git", "-C", root, "-c", "user.email=t@t.t", "-c", "user.name=t",
               "commit", "-q", "--allow-empty", "-m", "x")
        allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
        integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
        boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
        allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
        selection = instance_double(Saboteur::Engine::SubjectSelection, select: [], behavior_lines: nil)
        allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
        ignore_list = instance_double(Saboteur::IgnoreList, apply: [])
        allow(Saboteur::IgnoreList).to receive(:load).and_return(ignore_list)
        config = Saboteur::Config.new(scoped_config, root: root)
        described_class.new(config, err: StringIO.new).call
        expect(ignore_list).to have_received(:apply)
          .with([], subjects: [], unscoped_digests: nil, full_run: false)
      end
    end
  end

  # A scoped run still judges staleness against the unscoped candidate set,
  # so the engine must hand the selection's unscoped digests to the ignore
  # list (#284).
  it "threads the selection's unscoped digests through candidate_lists" do
    Dir.mktmpdir do |root|
      engine = described_class.new(Saboteur::Config.new({}, root: root), err: StringIO.new)
      subject = instance_double(Saboteur::Subject, id: "K#m")
      selection = instance_double(Saboteur::Engine::CandidateSelection,
                                  for: [], skipped_subjects: {}, selected: {},
                                  unscoped_digests: { "K#m" => %w[d1] })
      allow(Saboteur::Engine::CandidateSelection).to receive(:new).and_return(selection)
      engine.send(:candidate_lists, [subject], nil, instance_double(Saboteur::Selection::CoverageMap))
      expect(engine.instance_variable_get(:@unscoped_digests)).to eq("K#m" => %w[d1])
    end
  end
end
