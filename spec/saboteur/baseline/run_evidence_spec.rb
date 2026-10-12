# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "saboteur/baseline/run_evidence"

RSpec.describe Saboteur::Baseline::RunEvidence do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      example.run
    end
  end
  let(:config) { Saboteur::Config.new({}, root: @root) }
  let(:evidence) do
    subject
    described_class.new(config: config)
  end
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

  def finish(events: [], omissions: [], results: [result], stable_suite: true)
    evidence.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
    evidence.finish(results: results, stable_suite: stable_suite, skipped_subjects: {},
                    generation_events: events, omissions: omissions)
  end

  it "reconciles one fresh outcome with the pre-execution plan and immutable metadata" do
    captured = finish
    expect(captured.fetch("complete")).to be(true)
    expect(captured.fetch("issues")).to be_empty
    expect(captured.fetch("candidates").first.fetch("id")).to match(/\A[0-9a-f]{64}\z/)
    expect(captured.fetch("compatibility").fetch("config")).not_to have_key("json_report")
    expect(captured).to be_frozen
    expect(captured.fetch("candidates")).to be_frozen
  end

  it "retains a first invalid event even when the same text later records duplicate" do
    events = %w[invalid_syntax duplicate].map do |reason|
      Saboteur::Engine::Diagnostics::GenerationEvent.new(file: subject.file, subject: subject.id,
                                                         source: "builtin", operator: "bad", reason: reason)
    end
    captured = finish(events: events)
    expect(captured.fetch("complete")).to be(false)
    expect(captured.fetch("issues")).to include("generation:invalid_syntax:Probe#value:bad")
    expect(captured.fetch("generation_events").map do |event|
      event.fetch("reason")
    end).to eq(%w[invalid_syntax duplicate])
  end

  it "blocks missing results, cap omissions, skips, reused verdicts and unstable suite evidence" do
    omitted = Saboteur::Engine::Diagnostics::Omission.new(subject: subject.id, count: 2, limit: 1)
    captured = finish(omissions: [omitted], results: [], stable_suite: false)
    expect(captured.fetch("issues")).to include("unchanged_suite_incomplete", "omitted:Probe#value:2")
    expect(captured.fetch("issues").any? { |issue| issue.start_with?("missing_result:") }).to be(true)
  end

  it "blocks a reused verdict even when the terminal status is survived" do
    reused = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :survived,
                                        mutated_source: subject.apply(mutation.edits), reused: true)
    expect(finish(results: [reused]).fetch("issues")).to include("generation:reused:Probe#value")
  end

  it "blocks duplicate terminal outcomes rather than counting one verdict twice" do
    captured = finish(results: [result, result])
    expect(captured.fetch("complete")).to be(false)
    expect(captured.fetch("issues")).to include("duplicate_results")
  end

  it "blocks errors and skipped outcomes rather than treating missing evidence as detection" do
    %i[error resource_limit skipped].each do |status|
      other = Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: status,
                                         mutated_source: subject.apply(mutation.edits))
      fresh = described_class.new(config: config)
      fresh.plan([subject], [[[mutation, subject.apply(mutation.edits)]]])
      captured = fresh.finish(results: [other], stable_suite: true, skipped_subjects: {},
                              generation_events: [], omissions: [])
      expect(captured.fetch("complete")).to be(false)
    end
  end

  it "blocks input changes after capture" do
    evidence
    File.write(File.join(@root, "new.rb"), "changed")
    expect(finish.fetch("issues")).to include("inputs_unverified")
  end
end
