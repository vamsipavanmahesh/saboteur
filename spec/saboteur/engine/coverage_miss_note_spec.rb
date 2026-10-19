# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Engine::CoverageMissNote do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:cache_dir) { File.join(@root, ".saboteur") }
  let(:snapshot) { File.join(cache_dir, "inputs-coverage.json") }
  let(:hint) { "--test narrows the specs the build runs" }

  def write(name, body = "1\n")
    File.join(@root, name).tap { |path| File.write(path, body) }
  end

  def note(names, settings: "s1", clean: :itself.to_proc)
    described_class.new(cache_dir: cache_dir, root: @root, files: names.map { |name| File.join(@root, name) },
                        settings: settings, clean: clean)
  end

  def seed(names, settings: "s1")
    names.each { |name| write(name) }
    note(names, settings: settings).save
  end

  it "says there is nothing to compare with before any map was saved" do
    write("a.rb")

    expect(note(["a.rb"]).message(scoped: false)).to eq(
      "coverage cache miss: no earlier map to compare with; the map build runs the whole suite once; " \
      "--test narrows the specs the build runs"
    )
  end

  it "counts one edited file and names it" do
    seed(%w[a.rb b.rb])
    write("b.rb", "2\n")

    expect(note(%w[a.rb b.rb]).message(scoped: false)).to eq(
      "coverage cache miss: input files changed since the last map: 1 edited (b.rb); " \
      "the map build runs the whole suite once; #{hint}"
    )
  end

  it "names three changed files in full" do
    seed(%w[a.rb b.rb c.rb d.rb])
    %w[a.rb b.rb c.rb].each { |name| write(name, "2\n") }

    expect(note(%w[a.rb b.rb c.rb d.rb]).message(scoped: false))
      .to include("changed since the last map: 3 edited (a.rb, b.rb, c.rb);")
  end

  it "names the first three of four changed files and counts the rest" do
    seed(%w[a.rb b.rb c.rb d.rb e.rb])
    %w[a.rb b.rb c.rb d.rb].each { |name| write(name, "2\n") }

    expect(note(%w[a.rb b.rb c.rb d.rb e.rb]).message(scoped: false))
      .to include("changed since the last map: 4 edited (a.rb, b.rb, c.rb, +1 more);")
  end

  it "breaks changes into edited, added and removed, leaving out empty groups" do
    seed(%w[a.rb b.rb c.rb])
    write("a.rb", "2\n")
    File.delete(File.join(@root, "c.rb"))
    write("d.rb")
    write("e.rb")

    expect(note(%w[a.rb b.rb d.rb e.rb]).message(scoped: false))
      .to include("changed since the last map: 1 edited, 2 added, 1 removed (a.rb, c.rb, d.rb, +1 more);")
  end

  it "never reports more changed files than exist: removals alone read as removed" do
    seed(%w[a.rb b.rb])
    File.delete(File.join(@root, "b.rb"))

    expect(note(%w[a.rb]).message(scoped: false)).to include("changed since the last map: 1 removed (b.rb);")
  end

  it "treats a listed file that does not exist yet as different from one that now has content" do
    write("a.rb")
    note(%w[a.rb ghost.rb]).save
    write("ghost.rb")

    expect(note(%w[a.rb ghost.rb]).message(scoped: false))
      .to include("changed since the last map: 1 edited (ghost.rb);")
  end

  it "says settings or the version changed when no file did" do
    seed(%w[a.rb])

    expect(note(%w[a.rb], settings: "s2").message(scoped: false))
      .to include("coverage cache miss: settings or saboteur version changed;")
  end

  it "reports files and settings together" do
    seed(%w[a.rb])
    write("a.rb", "2\n")

    expect(note(%w[a.rb], settings: "s2").message(scoped: false))
      .to include("1 edited (a.rb); settings or saboteur version changed;")
  end

  it "does not claim the map file is gone when inputs match, only that it is missing or unusable" do
    seed(%w[a.rb])

    expect(note(%w[a.rb]).message(scoped: false))
      .to include("coverage cache miss: inputs match the last snapshot but its map file is missing or unusable;")
  end

  it "drops the --test remark and names the selected specs when --test already scoped the run" do
    write("a.rb")

    expect(note(["a.rb"]).message(scoped: true)).to eq(
      "coverage cache miss: no earlier map to compare with; the map build runs the selected specs once"
    )
  end

  it "does not mention --guess-tests, a deprecated no-op alias" do
    write("a.rb")

    expect(note(["a.rb"]).message(scoped: false)).not_to include("guess")
  end

  it "passes every shown path, current or from the old snapshot, through the cleaner" do
    seed(%w[a.rb b.rb])
    write("a.rb", "2\n")
    File.delete(File.join(@root, "b.rb"))
    write("c.rb")

    message = note(%w[a.rb c.rb], clean: ->(path) { "<#{path}>" }).message(scoped: false)
    expect(message).to include("(<a.rb>, <b.rb>, <c.rb>);")
  end

  it "treats a corrupt snapshot as no earlier map" do
    FileUtils.mkdir_p(cache_dir)
    File.write(snapshot, "{not json")
    write("a.rb")

    expect(note(["a.rb"]).message(scoped: false)).to include("no earlier map to compare with")
  end

  it "treats a snapshot that is not an object with files as no earlier map" do
    FileUtils.mkdir_p(cache_dir)
    File.write(snapshot, "[]")
    write("a.rb")

    expect(note(["a.rb"]).message(scoped: false)).to include("no earlier map to compare with")
  end

  it "treats a snapshot whose files entry is not an object as no earlier map" do
    FileUtils.mkdir_p(cache_dir)
    File.write(snapshot, '{"files": []}')
    write("a.rb")

    expect(note(["a.rb"]).message(scoped: false)).to include("no earlier map to compare with")
  end

  it "shows paths relative to the project root, and a path outside it as given" do
    outside = File.join(File.dirname(@root), "outside-#{Process.pid}.rb")
    File.write(outside, "1\n")
    seed(%w[a.rb])
    File.write(File.join(@root, "a.rb"), "2\n")
    names = described_class.new(cache_dir: cache_dir, root: @root, files: [File.join(@root, "a.rb"), outside],
                                settings: "s1", clean: :itself.to_proc)

    expect(names.message(scoped: false)).to include("1 edited, 1 added (#{outside}, a.rb);")
  ensure
    FileUtils.rm_f(outside)
  end

  describe "#save" do
    it "writes through a temp file renamed into place and leaves nothing else behind" do
      write("a.rb")
      allow(File).to receive(:rename).and_call_original
      note(["a.rb"]).save

      expect(File).to have_received(:rename).with("#{snapshot}.#{Process.pid}.tmp", snapshot)
      expect(Dir.children(cache_dir)).to eq(["inputs-coverage.json"])
    end

    it "ignores a write failure, so a good run is not aborted" do
      write("a.rb")
      allow(File).to receive(:write).and_raise(Errno::ENOSPC)

      expect { note(["a.rb"]).save }.not_to raise_error
    end

    it "ignores an unwritable cache directory" do
      write("a.rb")
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES)

      expect { note(["a.rb"]).save }.not_to raise_error
    end

    it "removes the temp file when the rename fails" do
      write("a.rb")
      allow(File).to receive(:rename).and_raise(Errno::EXDEV)
      note(["a.rb"]).save

      expect(Dir.children(cache_dir)).to eq([])
    end

    it "ignores a path that cannot be encoded as JSON" do
      FileUtils.mkdir_p(cache_dir)
      bad = described_class.new(cache_dir: cache_dir, root: @root, files: [write("a.rb")], settings: "s1",
                                clean: :itself.to_proc)
      bad.instance_variable_set(:@current, { "files" => { "\xff".b => "x" } })

      expect { bad.save }.not_to raise_error
    end
  end
end
