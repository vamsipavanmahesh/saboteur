# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "saboteur/baseline/run_evidence"

RSpec.describe Saboteur::Baseline::RunEvidence do
  around do |example|
    Dir.mktmpdir do |root|
      @root = File.realpath(root)
      example.run
    end
  end
  let(:config) { Saboteur::Config.new({}, root: @root) }
  let(:evidence) { described_class.new(config: config) }
  let(:subject) do
    path = File.join(@root, "probe.rb")
    File.write(path, "class Probe; def value; 1; end; end")
    Saboteur::SubjectFinder.new.call(path).subjects.first
  end
  let(:mutation) do
    start = subject.file_source.index("1")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: start, end_byte: start + 1,
                                              replacement: "0")
    Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "number", edits: [edit])
  end
  let(:result) do
    Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :survived,
                               mutated_source: subject.apply(mutation.edits))
  end

  def finish(skipped: {}, events: [], omissions: [])
    evidence.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
    evidence.finish(results: [result], stable_suite: true, skipped_subjects: skipped,
                    generation_events: events, omissions: omissions)
  end

  it "names the subject by its path relative to the root, without the root" do
    expect(finish.fetch("subjects")).to eq([["probe.rb", subject.id]])
  end

  it "reports each skipped subject as its id and reason" do
    issues = finish(skipped: { subject => "no_tests" }).fetch("issues")
    expect(issues).to eq(["subject_skipped:#{subject.id}:no_tests"])
  end

  it "reports each omission as its subject and count" do
    omitted = Saboteur::Engine::Diagnostics::Omission.new(subject: subject.id, count: 3, limit: 1)
    expect(finish(omissions: [omitted]).fetch("issues")).to eq(["omitted:#{subject.id}:3"])
  end

  it "keeps safe drops out of the generation issues and lists only the others, with their operator" do
    events = %w[unchanged duplicate invalid_syntax].map do |reason|
      Saboteur::Engine::Diagnostics::GenerationEvent.new(file: subject.file, subject: subject.id,
                                                         source: "builtin", operator: "op", reason: reason)
    end
    expect(finish(events: events).fetch("issues")).to eq(["generation:invalid_syntax:#{subject.id}:op"])
  end

  it "refuses a subject in a sibling directory whose name starts with the root's name" do
    sibling = "#{@root}-other"
    FileUtils.mkdir_p(sibling)
    path = File.join(sibling, "probe.rb")
    File.write(path, "class Probe; def value; 1; end; end")
    outside = Saboteur::SubjectFinder.new.call(path).subjects.first
    expect { evidence.plan([outside], [[]]) }
      .to raise_error(Saboteur::ConfigError, "baseline subject outside project root")
  ensure
    FileUtils.rm_rf(sibling)
  end
end
