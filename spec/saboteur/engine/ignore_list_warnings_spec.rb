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

  # A config-less Rails app defaults include to app/** (#1171); nobody set
  # it, so the run is still a full run for stale ignore entries (#1255).
  describe "a Rails app with no config file (#1255)" do
    def full_run_flag(root, overrides: {}, config: nil)
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      selection = instance_double(Saboteur::Engine::SubjectSelection, select: [], behavior_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
      ignore_list = instance_double(Saboteur::IgnoreList, apply: [])
      allow(Saboteur::IgnoreList).to receive(:load).and_return(ignore_list)
      described_class.new(config || Saboteur::Config.load(root: root, overrides: overrides), err: StringIO.new).call
      captured = nil
      expect(ignore_list).to have_received(:apply) { |*, **kwargs| captured = kwargs[:full_run] }
      captured
    end

    around do |example|
      Dir.mktmpdir do |dir|
        @root = File.realpath(dir)
        FileUtils.mkdir_p(File.join(@root, "config"))
        FileUtils.mkdir_p(File.join(@root, "app"))
        File.write(File.join(@root, "config", "application.rb"), "module Demo; class Application; end; end\n")
        example.run
      end
    end

    it "treats the detected Rails include as a full run" do
      expect(Saboteur::Config.load(root: @root)["include"]).to eq(Saboteur::Config::RAILS_INCLUDE)
      expect(full_run_flag(@root)).to be(true)
    end

    it "treats the same pattern given explicitly as a scoped run" do
      expect(full_run_flag(@root, overrides: { include: Saboteur::Config::RAILS_INCLUDE })).to be(false)
    end

    it "treats a narrowed include as scoped even when no key was marked explicit" do
      config = Saboteur::Config.new({ "include" => ["app/models/**/*.rb"] }, root: @root, explicit: [])
      expect(full_run_flag(@root, config: config)).to be(false)
    end

    it "treats a --subject filter as a scoped run" do
      expect(full_run_flag(@root, overrides: { subjects: ["User#name"] })).to be(false)
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
