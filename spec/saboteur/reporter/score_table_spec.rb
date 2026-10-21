# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

require "tmpdir"
require "fileutils"

RSpec.describe Saboteur::Reporter::ScoreTable do
  after { FileUtils.rm_rf(dir) }

  let(:out) { StringIO.new }
  let(:dir) { File.realpath(Dir.mktmpdir("saboteur-spec-")) }
  let(:palette) { Saboteur::Reporter::Palette.new(enabled: false) }

  def file_results(name, *statuses)
    path = File.join(dir, name)
    File.write(path, "class #{name.delete_suffix('.rb').capitalize}\n  def m; @a >= 1; end\nend\n")
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    at = subject.file_source.index(">=")
    statuses.map do |status|
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2, replacement: ">")
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits: [edit],
                                                        coarse: false)
      Saboteur::MutantResult.new(subject:, mutation:, status:, mutated_source: subject.apply(mutation.edits))
    end
  end

  def table_for(files)
    results = files.flat_map { |name, statuses| file_results(name, *statuses) }
    root = dir
    report = Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq, wall_time: 1.0, root:,
                                  warnings: [], seed: 1)
    described_class.new(out, palette).call(report)
    out.string
  end

  it "prints nothing for a single file" do
    expect(table_for("a.rb" => %i[killed survived])).to eq("")
  end

  it "prints two files, worst first, with padded scores and killed/tested counts" do
    text = table_for("good.rb" => %i[killed], "bad.rb" => %i[survived survived killed], "mid.rb" => %i[killed survived])
    expect(text).to eq(
      "\nScore by file (worst first):\n  bad.rb    33.3% (1/3)\n  " \
      "mid.rb    50.0% (1/2)\n  good.rb  100.0% (1/1)\n"
    )
  end

  it "lists fifteen files without a trailer, and counts the rest from sixteen" do
    fifteen = (1..15).to_h { |i| ["f#{i.to_s.rjust(2, '0')}.rb", %i[killed survived]] }
    expect(table_for(fifteen)).not_to include("more files")
    out.truncate(0)
    out.rewind
    sixteen = (1..17).to_h { |i| ["g#{i.to_s.rjust(2, '0')}.rb", %i[killed survived]] }
    text = table_for(sixteen)
    expect(text.lines.grep(/\.rb/).size).to eq(15)
    expect(text).to include("  ... 2 more files")
  end

  it "counts one extra file as one more" do
    sixteen = (1..16).to_h { |i| ["h#{i.to_s.rjust(2, '0')}.rb", %i[killed survived]] }
    expect(table_for(sixteen)).to include("  ... 1 more files")
  end
end
