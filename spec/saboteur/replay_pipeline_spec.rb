# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "replay wiring" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
  end

  let(:config) { Saboteur::Config.new({ "incremental" => true, "all" => true }) }
  let(:subject) { person_subject }
  let(:mutation) { comparison_mutation }
  let(:digest) { mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source) }
  let(:candidate) { [mutation, subject.apply(mutation.edits)] }
  let(:selection) { instance_double(Saboteur::Engine::SubjectSelection, select: [subject], behavior_lines: nil) }

  def engine(id = nil)
    described_class.new(config, err: StringIO.new, digest: id)
  end

  before do
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  it "skips the cache when incremental is off and nothing replays" do
    run = described_class.new(Saboteur::Config.new({ "all" => true }), err: StringIO.new)
    expect(run.send(:result_cache)).to be_nil
  end

  it "resolves one real candidate and bypasses caps and cache" do
    candidates = instance_double(Saboteur::Engine::Candidates, for: [candidate])
    allow(Saboteur::Engine::Candidates).to receive(:new).and_return(candidates)
    run = engine(digest)
    expect(run.send(:select_subjects, [])).to eq([[subject], nil])
    expect(run.send(:candidate_lists, [subject], nil, nil)).to eq([[candidate]])
    expect(run.send(:result_cache)).to be_nil
  end

  # The run hands the boot integration's test files to selection so --all
  # discovery follows the configured suite, not a root/spec guess (#319).
  it "wires the given test files into subject selection" do
    expect(Saboteur::Engine::SubjectSelection).to receive(:new)
      .with(anything, anything, test_files: ["spec/custom/a_spec.rb"], custom_map: anything).and_return(selection)
    expect(engine.send(:select_subjects, [], test_files: ["spec/custom/a_spec.rb"])).to eq([[subject], nil])
  end

  it "hands mutate's coverage map and subject files to the result cache (#197)" do
    run = engine
    map = instance_double(Saboteur::Selection::CoverageMap)
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: true, fetch: map)
    allow(run).to receive(:coverage_store).and_return(store)
    allow(run).to receive(:check_baseline)
    allow(run).to receive(:warn_unscoped)
    allow(run).to receive(:inform_about_run)
    allow(run).to receive(:abandon_for_budget?).and_return(false)
    allow(run).to receive(:scheduler_for)
    allow(run).to receive(:candidate_lists).and_return([[]])
    expect(run).to receive(:result_cache).with(map, ["lib/person.rb"]).and_call_original
    run.send(:mutate, [person_subject], ["lib/person.rb"], instance_double(Object), nil, [])
  end

  it "builds the cache with the coverage map and every loaded project file as fallback (#344)" do
    run = engine
    map = instance_double(Saboteur::Selection::CoverageMap)
    captured = nil
    allow(Saboteur::Engine::ResultCache).to receive(:new) do |kwargs|
      captured = kwargs
      instance_double(Saboteur::Engine::ResultCache)
    end
    run.send(:result_cache, map, ["lib/person.rb"])
    expect(captured[:coverage]).to eq(map)
    expect(captured[:fallback_files]).to include("lib/person.rb")
    expect(captured[:fallback_files]).to include(a_string_ending_with("/lib/saboteur/engine.rb"))
    root_prefix = "#{run.instance_variable_get(:@root)}/"
    expect(captured[:fallback_files]).to all(eq("lib/person.rb").or(start_with(root_prefix)))
    expect(captured[:fallback_files]).to all(end_with(".rb"))
  end

  it "excludes loaded files from a directory that merely shares the root's prefix (#353)" do
    run = engine
    sibling = "#{run.instance_variable_get(:@root)}-sibling/lib/evil.rb"
    $LOADED_FEATURES << sibling
    begin
      expect(run.send(:source_files, [])).not_to include(sibling)
    ensure
      $LOADED_FEATURES.delete(sibling)
    end
  end

  it "watches a loaded file with a non-ASCII name tagged US-ASCII under LANG=C (#353)" do
    run = engine
    accented = File.join(run.instance_variable_get(:@root), "lib", "héllo_probe_353.rb")
    feature = accented.dup.force_encoding(Encoding::US_ASCII)
    $LOADED_FEATURES.push(feature)
    begin
      expect(run.send(:source_files, [])).to include(accented)
    ensure
      $LOADED_FEATURES.delete(feature)
    end
  end

  # The probe lives in a temp project, never the repo's own lib/: other specs
  # (and parallel coverage parts) glob the real lib/ and would see it.
  it "watches loaded files reached through a symlinked root (#353)" do
    Dir.mktmpdir do |dir|
      root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(root, "lib"))
      probe = File.join(root, "lib", "symlink_probe_353.rb")
      File.write(probe, "# probe\n")
      link = File.join(dir, "link")
      File.symlink(root, link)
      run = described_class.new(Saboteur::Config.new({ "incremental" => true, "all" => true }, root: root),
                                err: StringIO.new)
      through_link = File.join(link, "lib", "symlink_probe_353.rb")
      $LOADED_FEATURES << through_link
      begin
        expect(run.send(:source_files, [])).to include(probe)
      ensure
        $LOADED_FEATURES.delete(through_link)
      end
    end
  end

  # The root itself can arrive in a spelling its realpath does not share
  # (macOS /var -> /private/var, a tmpdir symlink): a loaded feature whose
  # file is gone keeps the spelled path, and a resolved-root-only check
  # drops every loaded file from the watched set.
  it "watches loaded files when the root itself is a symlinked spelling (#353)" do
    Dir.mktmpdir do |target|
      Dir.mktmpdir do |parent|
        link = File.join(parent, "project")
        File.symlink(target, link)
        symlinked_config = Saboteur::Config.new({ "incremental" => true, "all" => true }, root: link)
        run = described_class.new(symlinked_config, err: StringIO.new)
        loaded = File.join(link, "lib", "lazy.rb")
        $LOADED_FEATURES.push(loaded)
        begin
          expect(run.send(:source_files, [])).to include(loaded)
        ensure
          $LOADED_FEATURES.delete(loaded)
        end
      end
    end
  end

  it "builds the cache with the suite digest that pins the run's support files (#344)" do
    run = engine
    map = instance_double(Saboteur::Selection::CoverageMap)
    suite_files = instance_double(Saboteur::Engine::SuiteFiles, digest: "suite-abc")
    allow(Saboteur::Engine::SuiteFiles).to receive(:new).and_return(suite_files)
    captured = nil
    allow(Saboteur::Engine::ResultCache).to receive(:new) do |kwargs|
      captured = kwargs
      instance_double(Saboteur::Engine::ResultCache)
    end
    run.send(:result_cache, map, ["lib/person.rb"])
    expect(captured[:suite_digest]).to eq("suite-abc")
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
    allow(selection).to receive(:behavior_lines).and_return(lines)
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
      arguments = { err: err, verbose: false, quiet: false }
      arguments[:digest] = digest if digest
      expect(Saboteur::Engine).to receive(:new).with(config, **arguments, palette: kind_of(Saboteur::Reporter::Palette))
                                               .and_return(engine_double(call: report))
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
