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

  def table_lines(files)
    results = files.flat_map { |name, statuses| file_results(name, *statuses) }
    report = Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq, wall_time: 1.0, root: dir,
                                  warnings: [], seed: 1)
    described_class.new(out, palette).call(report)
    out.string.lines.grep(/\.rb/).map { |line| line.split.first }
  end

  it "orders by score first, even when a lower score has fewer survivors" do
    names = table_lines("s.rb" => %i[killed killed killed killed killed survived survived], "r.rb" => %i[survived])
    expect(names).to eq(%w[r.rb s.rb])
  end

  it "puts the file with more survivors first among equal scores" do
    names = table_lines("x.rb" => %i[killed survived], "y.rb" => %i[killed killed survived survived])
    expect(names).to eq(%w[y.rb x.rb])
  end

  it "breaks a full tie by path" do
    expect(table_lines("z.rb" => %i[killed survived], "a.rb" => %i[killed survived])).to eq(%w[a.rb z.rb])
  end

  it "leaves out a file with nothing scored" do
    names = table_lines("a.rb" => %i[killed survived], "b.rb" => %i[killed], "none.rb" => %i[skipped])
    expect(names).to eq(%w[a.rb b.rb])
  end

  it "pads to the widest of the listed files, not of the files left out" do
    files = (1..15).to_h { |i| ["f#{i.to_s.rjust(2, '0')}.rb", %i[survived]] }
    files["a_much_longer_name_than_the_rest.rb"] = %i[killed]
    results = files.flat_map { |name, statuses| file_results(name, *statuses) }
    report = Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq, wall_time: 1.0, root: dir,
                                  warnings: [], seed: 1)
    described_class.new(out, palette).call(report)
    expect(out.string.lines[2]).to eq("  f01.rb    0.0% (0/1)\n")
  end
end
