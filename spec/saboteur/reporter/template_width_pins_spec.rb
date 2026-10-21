# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

# The report's fixed furniture stays within 80 columns at rest, so an
# 80-column terminal or CI log never wraps it mid-sentence. Lines carrying
# interpolated content - paths, subject ids, digests, source lines, run
# counts - are exempt: they grow with the repository under test.
RSpec.describe Saboteur::Reporter::Terminal, "fixed template line width" do
  # Glyph choice is locale-dependent; pin it so the width measured is the
  # UTF-8 one a modern terminal shows.
  around do |example|
    saved = ENV.fetch("LC_ALL", nil)
    ENV["LC_ALL"] = "C.UTF-8"
    example.run
  ensure
    saved ? ENV["LC_ALL"] = saved : ENV.delete("LC_ALL")
  end

  after { FileUtils.rm_rf(@dir) if @dir }

  it "keeps every fixed template line within 80 columns" do
    @dir = File.realpath(Dir.mktmpdir("saboteur-width-"))
    path = File.join(@dir, "widget.rb")
    File.write(path, "class Alpha\n  def one = 1 + 1\nend\n")
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    at = subject.file_source.index("+", subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1,
                                              replacement: "-")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "arithmetic",
                                                      edits: [edit], coarse: false)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits),
                                        covered_by: ["./spec/widget_spec.rb[2:1]"])
    report = Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0,
                                  root: @dir, warnings: [], seed: 1)

    out = StringIO.new
    described_class.new(out, color: :never).call(report)
    interpolated = [/\.rb/, /[0-9a-f]{16}/, /def one/, /^\s*\^/, /repeat with --seed/]
    offenders = out.string.lines.map(&:chomp).reject { |line| interpolated.any? { |re| line.match?(re) } }
                   .select { |line| line.length > 80 }
    expect(offenders).to be_empty

    closer = format(Saboteur::Reporter::DefaultFindings::CLOSER, more: 1000, findings: "findings")
    expect(closer.lines.map(&:chomp).map(&:length)).to all(be <= 80)
  end
end
