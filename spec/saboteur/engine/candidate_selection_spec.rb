# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::CandidateSelection do
  let(:subject_under_test) { subjects_in("class K\n  def m(a)\n    a + 1\n  end\nend\n").first }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:candidates) { instance_double(Saboteur::Engine::Candidates) }
  let(:map) { instance_double(Saboteur::Selection::CoverageMap) }
  let(:selection) { described_class.new(candidates: candidates, map: map, limit: 2, diagnostics: diagnostics) }

  before do
    allow(map).to receive(:preloaded?).and_return(false)
    allow(map).to receive(:boot_once?).and_return(false)
  end

  it "warns when a subject shows the boot-once signature (#575)" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return(%w[t1 t2])
    allow(map).to receive(:boot_once?).with(subject_under_test).and_return(true)
    allow(candidates).to receive(:for).with(subject_under_test).and_return([])

    selection.for(subject_under_test)

    expect(diagnostics.warnings).to include(
      "#{subject_under_test.id}: verify a survivor here by mutating the file on disk\n  " \
      "covered by every test and run at boot: mutants apply after boot, so a survivor " \
      "can be a boot-once effect the suite cannot re-observe (#575)"
    )
  end

  it "stays silent without the boot-once signature (#575)" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return(%w[t1])
    allow(candidates).to receive(:for).with(subject_under_test).and_return([])

    selection.for(subject_under_test)

    expect(diagnostics.warnings).to be_empty
  end

  it "records uncovered subjects without generating any mutants" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return([])
    allow(map).to receive(:ran_at_load?).with(subject_under_test.file, subject_under_test.coverage_lines)
                                        .and_return(false)
    allow(map).to receive(:empty_for?).with([subject_under_test.file]).and_return(false)
    expect(candidates).not_to receive(:for)
    expect(selection.for(subject_under_test)).to be_empty
    expect(selection.skipped_subjects).to eq(subject_under_test => "no coverage")
  end

  it "records a file no test touches as no tests, distinct from no coverage (C3)" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return([])
    allow(map).to receive(:ran_at_load?).with(subject_under_test.file, subject_under_test.coverage_lines)
                                        .and_return(false)
    allow(map).to receive(:empty_for?).with([subject_under_test.file]).and_return(true)
    expect(candidates).not_to receive(:for)
    expect(selection.for(subject_under_test)).to be_empty
    expect(selection.skipped_subjects).to eq(subject_under_test => "no tests")
  end

  it "classifies a subject in a file loaded before Coverage.start distinctly from no coverage" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return([])
    allow(map).to receive(:preloaded?).with(subject_under_test.file).and_return(true)
    expect(candidates).not_to receive(:for)

    expect(selection.for(subject_under_test)).to be_empty
    expect(selection.skipped_subjects).to eq(subject_under_test => "loaded before coverage started")
  end

  it "names an explicit skip reason before looking at coverage or generating mutants" do
    subject_under_test.skip_reason = "defined inside a block"
    expect(map).not_to receive(:tests_for)
    expect(candidates).not_to receive(:for)
    expect(selection.for(subject_under_test)).to be_empty
    expect(selection.skipped_subjects).to eq(subject_under_test => "defined inside a block")
  end

  it "names the explicit reason for an uncovered subject too, not no coverage" do
    subject_under_test.skip_reason = "refinements"
    allow(map).to receive(:tests_for).and_return([])
    expect(selection.for(subject_under_test)).to be_empty
    expect(selection.skipped_subjects.values).to eq(["refinements"])
  end

  it "records load-only subjects as ran at load: they ran, just never inside a test" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return([])
    allow(map).to receive(:ran_at_load?).with(subject_under_test.file, subject_under_test.coverage_lines)
                                        .and_return(true)
    expect(candidates).not_to receive(:for)
    expect(selection.for(subject_under_test)).to be_empty
    expect(selection.skipped_subjects)
      .to eq(subject_under_test => Saboteur::Selection::CoverageMap::RAN_AT_LOAD)
  end

  it "records each scoped subject's full candidate digests before the scope cuts them (#284)" do
    allow(map).to receive(:tests_for).and_return(["t1"])
    kept = double(digest: "aaa")
    dropped = double(digest: "bbb")
    list = [[kept, "x"], [dropped, "y"]]
    allow(candidates).to receive(:for).and_return(list)
    scope = instance_double(Saboteur::Engine::DiffScope)
    allow(scope).to receive(:restrict).with(subject_under_test, list).and_return([[kept, "x"]])
    selection.for(subject_under_test, scope: scope)
    expect(selection.unscoped_digests).to eq("K#m" => %w[aaa bbb])
  end

  it "records no unscoped digests for an unscoped run" do
    allow(map).to receive(:tests_for).and_return(["t1"])
    allow(candidates).to receive(:for).and_return([[:coarse, "nil"]])
    selection.for(subject_under_test)
    expect(selection.unscoped_digests).to eq({})
  end

  it "keeps the first candidates in deterministic coarse-first order and reports the omitted count" do
    allow(map).to receive(:tests_for).and_return(["t1"])
    list = [[:coarse, "nil"], [:coarse, "raise"], [:fine, "0"]]
    allow(candidates).to receive(:for).and_return(list)
    expect(selection.for(subject_under_test)).to eq(list.first(2))
    expect(selection.skipped_subjects).to be_empty
    expect(diagnostics.warnings).to include("K#m: omitted 1 mutant(s) above max_mutants_per_method (2)")
    expect(diagnostics.omissions).to eq([Saboteur::Engine::Diagnostics::Omission.new(subject: "K#m", count: 1,
                                                                                     limit: 2)])
  end

  it "does not warn when the candidate count equals the limit" do
    allow(map).to receive(:tests_for).and_return(["t1"])
    list = [[:coarse, "nil"], [:fine, "0"]]
    allow(candidates).to receive(:for).and_return(list)
    expect(selection.for(subject_under_test)).to eq(list)
    expect(diagnostics.warnings).to be_empty
    expect(diagnostics.omissions).to be_empty
  end

  it "restricts to changed lines before applying the limit" do
    allow(map).to receive(:tests_for).and_return(["t1"])
    list = [[double(digest: "d-out"), "a"], [double(digest: "d-ch1"), "b"], [double(digest: "d-ch2"), "c"]]
    allow(candidates).to receive(:for).and_return(list)
    scope = instance_double(Saboteur::Engine::DiffScope)
    allow(scope).to receive(:restrict).with(subject_under_test, list).and_return(list.last(2))
    expect(selection.for(subject_under_test, scope: scope)).to eq(list.last(2))
    expect(diagnostics.warnings).to be_empty
    expect(diagnostics.omissions).to be_empty
  end
  it "announces a skipped subject up front in a scoped run (#574)" do
    subject_under_test.skip_reason = "refinements"
    allow(map).to receive(:tests_for).and_return(["t1"])
    scope = instance_double(Saboteur::Engine::DiffScope)
    selection.for(subject_under_test, scope: scope)
    expect(diagnostics.warnings).to include("K#m (#{subject_under_test.file}:2): skipped (refinements); " \
                                            "its change is not verified by this run")
  end

  it "relativizes a skipped subject's announced location against the given root (#627)" do
    rooted = described_class.new(candidates: candidates, map: map, limit: 2, diagnostics: diagnostics,
                                 root: File.dirname(subject_under_test.file))
    subject_under_test.skip_reason = "refinements"
    scope = instance_double(Saboteur::Engine::DiffScope)
    rooted.for(subject_under_test, scope: scope)
    expect(diagnostics.warnings)
      .to include("K#m (subject_fixture.rb:2): skipped (refinements); its change is not verified by this run")
  end

  # #627 advisory: a skipped `def K.b` and a real `def self.b` in one class
  # share the id "K.b", so the announcement must name file:line to tell the
  # skip apart from the real subject.
  it "disambiguates a skipped constant-receiver def from a same-id real subject by file:line" do
    skipped, real = subjects_in("class K\n  def K.b; 1; end\n  def self.b; 2; end\nend\n")
    expect([skipped.id, real.id]).to eq(["K.b", "K.b"])
    allow(map).to receive(:tests_for).with(real).and_return(["t1"])
    allow(candidates).to receive(:for).with(real).and_return([])
    scope = instance_double(Saboteur::Engine::DiffScope)
    allow(scope).to receive(:restrict).with(real, []).and_return([])
    selection.for(skipped, scope: scope)
    selection.for(real, scope: scope)
    expect(diagnostics.warnings)
      .to include("K.b (#{skipped.file}:2): skipped (constant-receiver def); its change is not verified by this run")
    expect(selection.skipped_subjects.keys).to eq([skipped])
  end

  it "names the loaded specs when a scoped subject has no coverage (#636)" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return([])
    allow(map).to receive(:ran_at_load?).with(subject_under_test.file, subject_under_test.coverage_lines)
                                        .and_return(false)
    allow(map).to receive(:empty_for?).with([subject_under_test.file]).and_return(false)
    allow(map).to receive(:tests)
      .and_return(["./spec/models/widget_spec.rb[1:2]", "./spec/models/widget_spec.rb[1:1]",
                   "./spec/models/other_spec.rb[1:1]"])
    scope = instance_double(Saboteur::Engine::DiffScope)
    selection.for(subject_under_test, scope: scope)
    expect(diagnostics.warnings).to include(
      "K#m (#{subject_under_test.file}:2): skipped (no coverage); its change is not verified by this run - " \
      "loaded specs: spec/models/other_spec.rb, spec/models/widget_spec.rb; " \
      "other spec files may cover it, pass --test to load them"
    )
  end

  it "lists all five loaded specs without an ellipsis at the boundary (#636)" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return([])
    allow(map).to receive(:ran_at_load?).with(subject_under_test.file, subject_under_test.coverage_lines)
                                        .and_return(false)
    allow(map).to receive(:empty_for?).with([subject_under_test.file]).and_return(false)
    allow(map).to receive(:tests).and_return((1..5).map { |n| "./spec/m#{n}_spec.rb[1:1]" })
    scope = instance_double(Saboteur::Engine::DiffScope)
    selection.for(subject_under_test, scope: scope)
    expect(diagnostics.warnings).to include(
      "K#m (#{subject_under_test.file}:2): skipped (no coverage); its change is not verified by this run - " \
      "loaded specs: spec/m1_spec.rb, spec/m2_spec.rb, spec/m3_spec.rb, spec/m4_spec.rb, spec/m5_spec.rb; " \
      "other spec files may cover it, pass --test to load them"
    )
  end

  it "truncates to five loaded specs with an ellipsis at six (#636)" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return([])
    allow(map).to receive(:ran_at_load?).with(subject_under_test.file, subject_under_test.coverage_lines)
                                        .and_return(false)
    allow(map).to receive(:empty_for?).with([subject_under_test.file]).and_return(false)
    allow(map).to receive(:tests).and_return((1..6).map { |n| "./spec/m#{n}_spec.rb[1:1]" })
    scope = instance_double(Saboteur::Engine::DiffScope)
    selection.for(subject_under_test, scope: scope)
    expect(diagnostics.warnings).to include(
      "K#m (#{subject_under_test.file}:2): skipped (no coverage); its change is not verified by this run - " \
      "loaded specs: spec/m1_spec.rb, spec/m2_spec.rb, spec/m3_spec.rb, spec/m4_spec.rb, spec/m5_spec.rb and 1 more; " \
      "other spec files may cover it, pass --test to load them"
    )
  end

  it "says none when no specs were loaded (#636)" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return([])
    allow(map).to receive(:ran_at_load?).with(subject_under_test.file, subject_under_test.coverage_lines)
                                        .and_return(false)
    allow(map).to receive(:empty_for?).with([subject_under_test.file]).and_return(false)
    allow(map).to receive(:tests).and_return([])
    scope = instance_double(Saboteur::Engine::DiffScope)
    selection.for(subject_under_test, scope: scope)
    expect(diagnostics.warnings).to include(
      "K#m (#{subject_under_test.file}:2): skipped (no coverage); its change is not verified by this run - " \
      "loaded specs: none; other spec files may cover it, pass --test to load them"
    )
  end

  it "stays quiet for a skipped subject in an unscoped run" do
    subject_under_test.skip_reason = "refinements"
    allow(map).to receive(:tests_for).and_return(["t1"])
    selection.for(subject_under_test)
    expect(diagnostics.warnings).to be_empty
  end
end

RSpec.describe Saboteur::Engine::CandidateSelection, "real candidate pipeline" do
  it "validates, deduplicates, orders coarse first, restricts the diff, then caps proposals" do
    subject = subjects_in("class K\n  def m(a)\n    a + 1\n    a + 2\n  end\nend\n").first
    source = Class.new(Saboteur::MutationSource::Base) do
      def mutations_for(subject)
        [["a + 1", "a - 1", false], ["a + 2", "a +", false],
         ["a + 2", "a + 2", false], ["a + 2", "a - 2", false],
         ["a + 2", "a - 2", false], ["a + 2", "nil", true],
         ["a + 2", "a * 2", false]].map do |original, replacement, coarse|
          start = subject.file_source.index(original)
          edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: start,
                                                    end_byte: start + original.bytesize, replacement: replacement)
          Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: replacement,
                                                 edits: [edit], coarse: coarse)
        end
      end
    end.new
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    candidates = Saboteur::Engine::Candidates.new([source, source], diagnostics)
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 4 => ["t1"] } }, tests: ["t1"])
    scope = Saboteur::Engine::DiffScope.new(subject.file => Set[4])
    selection = described_class.new(candidates: candidates, map: map, limit: 2, diagnostics: diagnostics)
    selected = selection.for(subject, scope: scope)
    expect(selected.map { |mutation, _| mutation.operator }).to eq(["nil", "a - 2"])
    expect(diagnostics.invalid_mutations).to eq(1)
    expect(diagnostics.warnings).to eq(["K#m: dropped a + mutation (did not parse)",
                                        "K#m: omitted 1 mutant(s) above max_mutants_per_method (2)"])
  end
end
