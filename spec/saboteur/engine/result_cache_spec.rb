# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "tmpdir"

RSpec.describe Saboteur::Engine::ResultCache do
  let(:empty) { Saboteur::Selection::CoverageMap.new(lines: {}, tests: []) }

  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(@root, "spec"))
      File.write(File.join(@root, "spec", "person_spec.rb"), "# tests\n")
      File.write(File.join(@root, "Gemfile.lock"), "lock 1\n")
      example.run
    end
  end

  let(:path) { File.join(@root, ".saboteur", "results.json") }
  let(:tests) { ["./spec/person_spec.rb[1:1]"] }

  def cache
    described_class.new(path: path, root: @root, inputs: "config-1")
  end

  def killed(result_tests = tests)
    result_for(:killed, killed_by: result_tests.first(1), covered_by: result_tests, kill_cause: "assertion",
                        runtime: 0.2)
  end

  def stored
    cache.tap { |store| store.record(killed) }.save
  end

  it "returns a stored verdict while nothing it depends on changed" do
    stored
    reused = cache.lookup(person_subject, comparison_mutation, tests)
    expect(reused.values_at(:status, :killed_by, :kill_cause)).to eq([:killed, tests.first(1), "assertion"])
  end

  it "forgets it when a covering test file changes" do
    stored
    File.write(File.join(@root, "spec", "person_spec.rb"), "# tests, edited\n")
    expect(cache.lookup(person_subject, comparison_mutation, tests)).to be_nil
  end

  it "forgets it when the set of covering tests changes" do
    stored
    expect(cache.lookup(person_subject, comparison_mutation, tests + ["./spec/person_spec.rb[1:2]"])).to be_nil
  end

  it "forgets it when the lockfile or the run's inputs change" do
    stored
    File.write(File.join(@root, "Gemfile.lock"), "lock 2\n")
    expect(cache.lookup(person_subject, comparison_mutation, tests)).to be_nil
    File.write(File.join(@root, "Gemfile.lock"), "lock 1\n")
    other_inputs = described_class.new(path: path, root: @root, inputs: "config-2")
    expect(other_inputs.lookup(person_subject, comparison_mutation, tests)).to be_nil
  end

  it "forgets it when the method's source changes" do
    stored
    edited = subjects_in(ReportHelpers::PERSON.sub("@age >= 18", "@age >= 18 && true"), name: "person.rb").first
    expect(cache.lookup(edited, comparison_mutation, tests)).to be_nil
  end

  # The method reads CAP, defined above the class. Changing CAP changes the
  # file but not the method text, and the mutant (>= to >) is the same.
  def subject_with_cap(value)
    source = "CAP = #{value}\nclass Person\n  def adult?; @age >= CAP; end\nend\n"
    subjects_in(source, name: "person.rb").first
  end

  def comparison_mutation_in(subject)
    at = subject.file_source.index(">=")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2, replacement: ">")
    Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits: [edit],
                                           coarse: false)
  end

  it "forgets it when the file outside the method changes (a constant the method reads)" do
    first = subject_with_cap(100)
    mutation = comparison_mutation_in(first)
    store = cache
    store.record(Saboteur::MutantResult.new(subject: first, mutation:, status: :killed,
                                            mutated_source: first.apply(mutation.edits),
                                            killed_by: tests.first(1), covered_by: tests,
                                            kill_cause: "assertion", runtime: 0.2))
    store.save
    edited = subject_with_cap(500)
    expect(edited.source).to eq(first.source)
    expect(cache.lookup(edited, comparison_mutation_in(edited), tests)).to be_nil
  end

  it "forgets it when the suite's shared files change (support, helpers)" do
    store = described_class.new(path: path, root: @root, inputs: "config-1", suite_digest: "support-1")
    store.record(killed)
    store.save
    later = described_class.new(path: path, root: @root, inputs: "config-1", suite_digest: "support-2")
    expect(later.lookup(person_subject, comparison_mutation, tests)).to be_nil
  end

  it "ignores a results file in another format" do
    stored
    data = JSON.parse(File.read(path))
    File.write(path, JSON.generate(data.merge("format" => 99)))
    expect(cache.lookup(person_subject, comparison_mutation, tests)).to be_nil
  end

  # #197: the verdict also depends on every file a covering test touched -
  # a constant or method defined in another file can flip it.
  def with_dependency_files
    FileUtils.mkdir_p(File.join(@root, "lib"))
    File.write(File.join(@root, "lib", "helper.rb"), "CAP = 100\n")
    File.write(File.join(@root, "lib", "unrelated.rb"), "OTHER = 1\n")
    yield File.join(@root, "lib", "helper.rb"), File.join(@root, "lib", "unrelated.rb")
  end

  def coverage_for(map)
    Saboteur::Selection::CoverageMap.new(lines: map, tests: tests)
  end

  it "forgets it when a file the covering test touches changes (#197)" do
    with_dependency_files do |helper, _unrelated|
      coverage = coverage_for(helper => { 1 => tests })
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      store.record(killed)
      store.save
      File.write(helper, "CAP = 500\n")
      again = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      expect(again.lookup(person_subject, comparison_mutation, tests)).to be_nil
    end
  end

  it "keeps it when only a file no covering test touches changes (#197)" do
    with_dependency_files do |helper, unrelated|
      coverage = coverage_for(helper => { 1 => tests })
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      store.record(killed)
      store.save
      File.write(unrelated, "OTHER = 2\n")
      again = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      expect(again.lookup(person_subject, comparison_mutation, tests)).not_to be_nil
    end
  end

  it "watches every source file when the dependency set is unknown, from root-relative paths (#197)" do
    with_dependency_files do |_helper, unrelated|
      files = ["lib/helper.rb", "lib/unrelated.rb"]
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage: empty, fallback_files: files)
      store.record(killed)
      store.save
      File.write(unrelated, "OTHER = 2\n")
      again = described_class.new(path: path, root: @root, inputs: "config-1", coverage: empty, fallback_files: files)
      expect(again.lookup(person_subject, comparison_mutation, tests)).to be_nil
    end
  end

  it "sees the same fingerprint however the fallback files were ordered (#197)" do
    with_dependency_files do |helper, unrelated|
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage: empty,
                                  fallback_files: [helper, unrelated])
      store.record(killed)
      store.save
      reordered = described_class.new(path: path, root: @root, inputs: "config-1", coverage: empty,
                                      fallback_files: [unrelated, helper])
      expect(reordered.lookup(person_subject, comparison_mutation, tests)).not_to be_nil
    end
  end

  it "treats an empty coverage map as an unknown dependency set (#197)" do
    with_dependency_files do |_helper, unrelated|
      files = [unrelated]
      empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage: empty,
                                  fallback_files: files)
      store.record(killed)
      store.save
      File.write(unrelated, "OTHER = 2\n")
      again = described_class.new(path: path, root: @root, inputs: "config-1", coverage: empty,
                                  fallback_files: files)
      expect(again.lookup(person_subject, comparison_mutation, tests)).to be_nil
    end
  end

  it "never stores errors or skips: they always run again" do
    store = cache
    store.record(result_for(:error, covered_by: tests))
    store.record(result_for(:skipped, reason: "no coverage"))
    store.save
    expect(cache.lookup(person_subject, comparison_mutation, tests)).to be_nil
  end
  it "computes the unobserved set once across repeated lookups (#353)" do
    with_dependency_files do |helper, caller_file|
      coverage = Saboteur::Selection::CoverageMap.new(lines: { caller_file => { 1 => tests } }, tests: tests,
                                                      loaded_files: [helper])
      allow(coverage).to receive(:empty_for?).and_call_original
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      store.record(killed)
      store.save

      2.times { store.lookup(person_subject, comparison_mutation, tests) }

      expect(coverage).to have_received(:empty_for?).once
    end
  end

  it "forgets it when a lazily required source outside the include list changes (#353)" do
    with_dependency_files do |helper, caller_file|
      coverage = Saboteur::Selection::CoverageMap.new(lines: { caller_file => { 1 => tests } }, tests: tests,
                                                      loaded_files: [helper])
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      store.record(killed)
      store.save

      File.write(helper, "CAP = 500
  ")

      again = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      expect(again.lookup(person_subject, comparison_mutation, tests)).to be_nil
    end
  end

  it "still keeps it when the lazily required source is unchanged (#353)" do
    with_dependency_files do |helper, caller_file|
      coverage = Saboteur::Selection::CoverageMap.new(lines: { caller_file => { 1 => tests } }, tests: tests,
                                                      loaded_files: [helper])
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      store.record(killed)
      store.save

      again = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      expect(again.lookup(person_subject, comparison_mutation, tests)).not_to be_nil
    end
  end

  it "forgets it when a helper with only method coverage changes, for an endless def (#344)" do
    with_dependency_files do |helper, caller_file|
      coverage = Saboteur::Selection::CoverageMap.new(
        lines: { caller_file => { 1 => tests } },
        methods: { helper => { 1 => tests } },
        tests: tests
      )
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      store.record(killed)
      store.save
      File.write(helper, "CAP = 500
")
      again = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      expect(again.lookup(person_subject, comparison_mutation, tests)).to be_nil
    end
  end

  it "forgets it when a file loaded before the suite changes, with a nonempty map (#344)" do
    with_dependency_files do |boot, caller_file|
      coverage = Saboteur::Selection::CoverageMap.new(
        lines: { caller_file => { 1 => tests } },
        load_lines: { boot => { 1 => 1 } },
        tests: tests
      )
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      store.record(killed)
      store.save
      File.write(boot, "CAP = 500
")
      again = described_class.new(path: path, root: @root, inputs: "config-1", coverage:)
      expect(again.lookup(person_subject, comparison_mutation, tests)).to be_nil
    end
  end

  it "forgets it when a loaded source the map never observed changes, with a nonempty map (#344)" do
    with_dependency_files do |observed, outside|
      coverage = Saboteur::Selection::CoverageMap.new(lines: { observed => { 1 => tests } }, tests: tests)
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage:,
                                  fallback_files: [outside])
      store.record(killed)
      store.save
      File.write(outside, "OTHER = 2
")
      again = described_class.new(path: path, root: @root, inputs: "config-1", coverage:,
                                  fallback_files: [outside])
      expect(again.lookup(person_subject, comparison_mutation, tests)).to be_nil
    end
  end
  it "keeps it when a file only other tests touched changes - observed, so not conservatively watched (#344)" do
    with_dependency_files do |helper, others|
      coverage = Saboteur::Selection::CoverageMap.new(
        lines: { helper => { 1 => tests }, others => { 1 => ["./spec/other_spec.rb[1:1]"] } },
        tests: tests
      )
      store = described_class.new(path: path, root: @root, inputs: "config-1", coverage:,
                                  fallback_files: [others])
      store.record(killed)
      store.save
      File.write(others, "OTHER = 2
")
      again = described_class.new(path: path, root: @root, inputs: "config-1", coverage:,
                                  fallback_files: [others])
      expect(again.lookup(person_subject, comparison_mutation, tests)).not_to be_nil
    end
  end
end
