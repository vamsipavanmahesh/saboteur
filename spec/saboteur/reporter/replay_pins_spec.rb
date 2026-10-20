# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe Saboteur::Reporter::Replay do
  after { FileUtils.rm_rf(dir) }

  let(:dir) { File.realpath(Dir.mktmpdir("saboteur-spec-")) }
  let(:result) do
    path = File.join(dir, "probe.rb")
    File.write(path, "class Probe\n  def m; @a >= 1; end\nend\n")
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    at = subject.file_source.index(">=")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2, replacement: ">")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits: [edit],
                                                      coarse: false)
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived, mutated_source: subject.apply(mutation.edits))
  end

  it "heads each replay with the subject, operator, digest and status, after a blank line" do
    out = StringIO.new
    report = Saboteur::Report.new(results: [result], subjects: [result.subject], wall_time: 1.0, root: dir,
                                  warnings: [], seed: 1)
    described_class.new(out).call(report)
    expect(out.string).to start_with(
      "\nReplay: #{result.subject.id} comparison #{result.digest} (survived)\n"
    )
    expect(out.string).to include("Selected tests:\n  none\n")
  end
end
