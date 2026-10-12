# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::HazardGuard do
  def partition(source, patterns: nil)
    subject = subjects_in("class K\n  def m\n#{source}\n  end\nend\n").first
    mutations = Saboteur::MutationSource::Builtin.new.mutations_for(subject)
    guard = described_class.new(patterns || described_class::DEFAULT_HAZARD)
    kept, suppressed = guard.partition(mutations.map { |mutation| [mutation, nil] }, subject)
    [kept.map(&:first).map(&:operator), suppressed.map(&:first).map(&:operator), subject, mutations]
  end

  it "suppresses mutants inside the arguments of FileUtils.rm_rf (issue #102)" do
    _kept, suppressed, = partition('    FileUtils.rm_rf(File.join(Dir.pwd, "build"))')
    expect(suppressed).to include("literal_string", "argument_removal")
  end

  it "keeps the coarse mutants that destroy the call instead of running it" do
    kept, _suppressed, = partition('    FileUtils.rm_rf(File.join(Dir.pwd, "build"))')
    expect(kept).to include("body_nil", "body_raise")
  end

  it "suppresses bare Kernel process spawns" do
    _kept, suppressed, = partition('    system("make clean")')
    expect(suppressed).to include("literal_string")
  end

  it "treats backticks/%x literals as hazardous spans" do
    source = "class K\n  def m\n    `ls -la`\n  end\nend\n"
    subject = subjects_in(source).first
    xstring_start = subject.file_source.index("`")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: xstring_start + 1,
                                              end_byte: xstring_start + 3, replacement: "rm")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "literal_string",
                                                      edits: [edit])
    _kept, suppressed = described_class.new.partition([[mutation, nil]], subject)
    expect(suppressed.map(&:first)).to eq([mutation])
  end

  it "suppresses a negation removal whose replacement keeps the call alive" do
    _kept, suppressed, = partition('    keep if !system("make")')
    expect(suppressed).to include("negation_removal")
  end

  it "suppresses Open3, IO.popen and rmtree on any receiver" do
    _k1, s1, = partition('    Open3.capture2("ls")')
    _k2, s2, = partition('    IO.popen("ls")')
    _k3, s3, = partition("    path.rmtree")
    expect(s1 + s2 + s3).not_to be_empty
  end

  it "suppresses Kernel#open with a leading pipe but leaves a plain open alone" do
    _kept, suppressed, = partition('    open("| ls")')
    expect(suppressed).not_to be_empty
    kept, suppressed2, = partition('    open("file.txt")')
    expect(suppressed2).to be_empty
    expect(kept).to include("literal_string")
  end

  it "leaves ordinary calls fully mutable" do
    _kept, suppressed, = partition('    File.read("build/out.txt")')
    expect(suppressed).to be_empty
  end

  it "honours custom hazard patterns" do
    guard_tags = ["Deploys.destroy_everything"]
    _kept, suppressed, = partition('    Deploys.destroy_everything("prod")', patterns: guard_tags)
    expect(suppressed).to include("literal_string")
  end

  it "suppresses any Open3 method, not only the common ones" do
    _kept, suppressed, = partition('    Open3.pipeline("cat a", "grep b")')
    expect(suppressed).not_to be_empty
  end

  it "still catches rmtree by name with a custom pattern list" do
    _kept, suppressed, = partition('    rmtree("build")', patterns: ["Deploys.destroy_everything"])
    expect(suppressed).not_to be_empty
  end

  it "does not treat a pipe string handed to other methods as a spawn" do
    _kept, suppressed, = partition('    foo("| ls")')
    expect(suppressed).to be_empty
  end

  it "suppresses Kernel#open with an interpolated argument that starts with a pipe" do
    _kept, suppressed, = partition('    open("| #{dir} -la")') # rubocop:disable Lint/InterpolationCheck
    expect(suppressed).not_to be_empty
  end

  it "leaves an interpolated open argument that starts with plain text alone" do
    _kept, suppressed, = partition('    open("file #{dir}.txt")') # rubocop:disable Lint/InterpolationCheck
    expect(suppressed).to be_empty
  end

  it "leaves an open whose argument is a plain variable alone" do
    _kept, suppressed, = partition("    open(path)")
    expect(suppressed).to be_empty
  end

  it "leaves an interpolated open argument without a leading pipe alone" do
    _kept, suppressed, = partition('    open("#{dir}| ls")') # rubocop:disable Lint/InterpolationCheck
    expect(suppressed).to be_empty
  end

  it "does not descend into a call nested inside a hazardous one" do
    source = "class K\n  def m\n    FileUtils.rm_rf(`ls -la`)\n  end\nend\n"
    subject = subjects_in(source).first
    span_start = subject.file_source.index("FileUtils.rm_rf")
    span_end = span_start + "FileUtils.rm_rf(`ls -la`)".size
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: span_start,
                                              end_byte: span_end, replacement: "backup(`ls -la`)")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit])
    kept, suppressed = described_class.new.partition([[mutation, nil]], subject)
    expect([kept.size, suppressed.size]).to eq([1, 0])
  end

  it "suppresses an explicit Kernel.open with a leading pipe" do
    _kept, suppressed, = partition('    Kernel.open("| ls")')
    expect(suppressed).not_to be_empty
  end

  it "leaves open on other receivers alone even with a pipe string" do
    _kept, suppressed, = partition('    Foo.open("| ls")')
    expect(suppressed).to be_empty
  end

  it "handles a bare open with no arguments" do
    _kept, suppressed, = partition("    open()")
    expect(suppressed).to be_empty
  end

  it "suppresses only edits that genuinely touch a hazardous span" do
    source = "class K\n  def m\n    FileUtils.rm_rf(File.join(Dir.pwd, \"build\"))\n  end\nend\n"
    subject = subjects_in(source).first
    guard = described_class.new
    span_start = subject.file_source.index("FileUtils.rm_rf")
    span_end = span_start + "FileUtils.rm_rf(File.join(Dir.pwd, \"build\"))".size

    def mutation_at(subject, start_byte, end_byte, replacement: "x")
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: start_byte,
                                                end_byte: end_byte, replacement: replacement)
      Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
    end

    kept_cases = {
      "strictly left of the call" => [span_start - 5, span_start - 2],
      "abutting the call on the left" => [span_start - 3, span_start],
      "abutting the call on the right" => [span_end, span_end + 3],
      "strictly right of the call" => [span_end + 2, span_end + 5],
      "covering the call with overflow on the left" => [span_start - 2, span_end],
      "covering the call with overflow on the right" => [span_start, span_end + 2],
      "covering the call exactly" => [span_start, span_end]
    }
    kept_cases.each do |label, (start_byte, end_byte)|
      kept, suppressed = guard.partition([[mutation_at(subject, start_byte, end_byte), nil]], subject)
      expect([kept.size, suppressed.size]).to eq([1, 0]), "expected edit #{label} to be kept"
    end

    suppressed_cases = {
      "inside the call" => [span_start + 3, span_end - 3],
      "from inside the call past its end" => [span_start + 3, span_end + 2],
      "from before the call into its interior" => [span_start - 2, span_end - 2]
    }
    suppressed_cases.each do |label, (start_byte, end_byte)|
      kept, suppressed = guard.partition([[mutation_at(subject, start_byte, end_byte), nil]], subject)
      expect([kept.size, suppressed.size]).to eq([0, 1]), "expected edit #{label} to be suppressed"
    end

    same_call = mutation_at(subject, span_start, span_end,
                            replacement: "FileUtils.rm_rf(File.join(Dir.pwd, \"build\"))")
    kept, suppressed = guard.partition([[same_call, nil]], subject)
    expect([kept.size, suppressed.size]).to eq([0, 1])
  end
end
