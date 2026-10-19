# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Saboteur::Engine::PartialInvalidation do
  let(:root) { "/proj" }
  let(:a_src) { "/proj/lib/a.rb" }
  let(:b_src) { "/proj/lib/b.rb" }
  let(:durations) { %w[x y z w].to_h { |name| ["./spec/#{name}_spec.rb[1:1]", 1] } }
  let(:lines) do
    { a_src => { 1 => %w[./spec/z_spec.rb[1:1] ./spec/x_spec.rb[1:1]] }, b_src => { 1 => %w[./spec/y_spec.rb[1:1]] } }
  end
  let(:extra) { {} }
  let(:tests) do
    %w[./spec/z_spec.rb[1:1] ./spec/z_spec.rb[1:2] ./spec/y_spec.rb[1:1] ./spec/x_spec.rb[1:1] ./spec/w_spec.rb[1:1]]
  end
  let(:map) do
    Saboteur::Selection::CoverageMap.new(
      lines: lines, tests: tests, durations: durations, **extra
    )
  end
  let(:files) do
    { "lib/a.rb" => "1" * 64, "lib/b.rb" => "2" * 64, "spec/x_spec.rb" => "3" * 64, "spec/y_spec.rb" => "4" * 64,
      "spec/z_spec.rb" => "5" * 64, "spec/w_spec.rb" => "6" * 64, "spec/fixtures/data.yml" => "7" * 64,
      "spec/spec_helper.rb" => "8" * 64 }
  end
  let(:base) { { "format" => 1, "root" => "r", "runtime" => "t", "settings" => "s", "files" => files } }
  let(:invalidation) do
    described_class.new(map: map, root: root, included: %w[lib/a.rb lib/b.rb],
                        spec_files: %w[spec/x_spec.rb spec/y_spec.rb spec/z_spec.rb spec/w_spec.rb])
  end

  def current(changes = {}, top = {})
    base.merge(top).merge("files" => files.merge(changes))
  end

  def stale(changes = {}, top = {})
    invalidation.stale_specs(base, current(changes, top))
  end

  it "needs nothing rerun when no input changed" do
    expect(stale).to eq([])
  end

  it "reruns a changed spec file and nothing else" do
    expect(stale("spec/y_spec.rb" => "9" * 64)).to eq(%w[spec/y_spec.rb])
  end

  it "reruns the specs that covered a changed source, once each, in the full run's order" do
    expect(stale("lib/a.rb" => "9" * 64)).to eq(%w[spec/z_spec.rb spec/x_spec.rb])
  end

  it "keeps the full run's order for specs reached by different changes" do
    expect(stale("spec/x_spec.rb" => "8" * 64, "spec/z_spec.rb" => "9" * 64)).to eq(%w[spec/z_spec.rb spec/x_spec.rb])
  end

  it "reruns a changed spec file that recorded no test, after the others" do
    inv = described_class.new(map: map, root: root, included: %w[lib/a.rb],
                              spec_files: %w[spec/x_spec.rb spec/v_spec.rb])
    snap = base.merge("files" => files.merge("spec/v_spec.rb" => "a" * 64))
    after = snap.merge("files" => snap["files"].merge("spec/v_spec.rb" => "b" * 64, "spec/x_spec.rb" => "9" * 64))
    expect(inv.stale_specs(snap, after)).to eq(%w[spec/x_spec.rb spec/v_spec.rb])
  end

  it "goes full when a non-Ruby fixture a test may read changed" do
    expect(stale("spec/fixtures/data.yml" => "9" * 64)).to eq(:full)
  end

  it "goes full when a fixture beside a test directory other than spec/ changed" do
    snap = { "files" => { "test/fixtures/d.yml" => "1" * 64, "test/a_test.rb" => "2" * 64 } }
    inv = described_class.new(map: map, root: root, included: [], spec_files: %w[test/a_test.rb])
    full = base.merge(snap)
    expect(inv.stale_specs(full,
                           full.merge("files" => { "test/fixtures/d.yml" => "9" * 64, "test/a_test.rb" => "2" * 64 })))
      .to eq(:full)
  end

  it "goes full when a shared support file changed" do
    expect(stale("spec/spec_helper.rb" => "9" * 64)).to eq(:full)
  end

  it "goes full when an included source without coverage evidence changed" do
    inv = described_class.new(map: map, root: root, included: %w[lib/a.rb lib/b.rb lib/c.rb],
                              spec_files: %w[spec/x_spec.rb])
    snap = base.merge("files" => files.merge("lib/c.rb" => "1" * 64))
    expect(inv.stale_specs(snap, snap.merge("files" => snap["files"].merge("lib/c.rb" => "2" * 64)))).to eq(:full)
  end

  it "goes full when a changed source file is not in the include set" do
    inv = described_class.new(map: map, root: root, included: %w[lib/b.rb],
                              spec_files: %w[spec/x_spec.rb spec/z_spec.rb])
    expect(inv.stale_specs(base, current("lib/a.rb" => "9" * 64))).to eq(:full)
  end

  context "when a covering test id does not name a spec file of the suite" do
    let(:lines) { { a_src => { 1 => %w[./spec/z_spec.rb[1:1] shared_examples:42] } } }

    it("goes full") { expect(stale("lib/a.rb" => "9" * 64)).to eq(:full) }
  end

  context "when the changed source ran while the app loaded" do
    let(:extra) { { load_lines: { a_src => [1] } } }

    it("goes full") { expect(stale("lib/a.rb" => "9" * 64)).to eq(:full) }
  end

  context "when the changed source has line entries but no test behind any of them" do
    let(:lines) { { a_src => { 1 => [], 2 => [] } } }
    let(:extra) { { methods: { a_src => { 1 => [] } } } }

    it("has no evidence, so goes full") { expect(stale("lib/a.rb" => "9" * 64)).to eq(:full) }
  end

  context "when the changed source has an empty load-lines entry" do
    let(:extra) { { load_lines: { a_src => [] }, load_methods: { a_src => {} } } }

    it("does not count it as boot code") {
      expect(stale("lib/a.rb" => "9" * 64)).to eq(%w[spec/z_spec.rb spec/x_spec.rb])
    }
  end

  context "when the changed source has an empty line entry and no method entry" do
    let(:lines) { { a_src => {} } }

    it("has no evidence, so goes full") { expect(stale("lib/a.rb" => "9" * 64)).to eq(:full) }
  end

  context "when the changed source recorded only a load-time method call" do
    let(:extra) { { load_methods: { a_src => { 1 => ["boot"] } } } }

    it("goes full") { expect(stale("lib/a.rb" => "9" * 64)).to eq(:full) }
  end

  context "when the changed source was loaded before coverage started" do
    let(:extra) { { preloaded: [a_src] } }

    it("goes full") { expect(stale("lib/a.rb" => "9" * 64)).to eq(:full) }
  end

  context "when a source has only method evidence (an endless def)" do
    let(:lines) { { a_src => {} } }
    let(:extra) { { methods: { a_src => { 1 => %w[./spec/w_spec.rb[1:1]] } } } }

    it("counts it as evidence") { expect(stale("lib/a.rb" => "9" * 64)).to eq(%w[spec/w_spec.rb]) }
  end

  it "goes full for an added file, even a spec file" do
    expect(stale("spec/new_spec.rb" => "9" * 64)).to eq(:full)
  end

  it "goes full for a removed file" do
    expect(invalidation.stale_specs(base, current.merge("files" => files.except("spec/y_spec.rb")))).to eq(:full)
  end

  it "goes full when a file is unreadable on either side, changed or not" do
    expect(stale("spec/y_spec.rb" => false)).to eq(:full)
    unreadable = base.merge("files" => files.merge("spec/y_spec.rb" => false))
    expect(invalidation.stale_specs(unreadable, current)).to eq(:full)
  end

  %w[format root runtime settings].each do |key|
    it "goes full when the snapshot's #{key} differs" do
      expect(stale({}, { key => "other" })).to eq(:full)
    end
  end

  describe "the stale share threshold" do
    let(:files) { super().merge("spec/v_spec.rb" => "a" * 64) }
    let(:durations) { { "./spec/x_spec.rb[1:1]" => 5, "./spec/y_spec.rb[1:1]" => 5 } }
    let(:lines) { { a_src => { 1 => %w[./spec/x_spec.rb[1:1]] } } }
    let(:invalidation) do
      described_class.new(map: map, root: root, included: %w[lib/a.rb], spec_files: %w[spec/x_spec.rb spec/y_spec.rb])
    end
    let(:map) do
      Saboteur::Selection::CoverageMap.new(lines: lines, tests: durations.keys, durations: durations)
    end

    it "stays partial at exactly half of the recorded time" do
      expect(stale("spec/x_spec.rb" => "9" * 64)).to eq(%w[spec/x_spec.rb])
    end

    it "goes full just above half" do
      durations["./spec/x_spec.rb[1:1]"] = 5.01
      expect(stale("spec/x_spec.rb" => "9" * 64)).to eq(:full)
    end

    it "stays partial just below half" do
      durations["./spec/x_spec.rb[1:1]"] = 4.99
      expect(stale("spec/x_spec.rb" => "9" * 64)).to eq(%w[spec/x_spec.rb])
    end

    it "weights by spec file, so two tests in one file count together" do
      durations.replace("./spec/x_spec.rb[1:1]" => 3, "./spec/x_spec.rb[1:2]" => 3, "./spec/y_spec.rb[1:1]" => 4)
      expect(invalidation.stale_specs(base, current("spec/x_spec.rb" => "9" * 64))).to eq(:full)
    end

    it "counts a test with no recorded duration as zero seconds, on either side of the share" do
      durations.replace("./spec/x_spec.rb[1:1]" => 1, "./spec/z_spec.rb[1:1]" => 1)
      map_tests = %w[./spec/x_spec.rb[1:1] ./spec/y_spec.rb[1:1] ./spec/z_spec.rb[1:1]]
      allow(map).to receive(:tests).and_return(map_tests)
      expect(stale("spec/x_spec.rb" => "9" * 64)).to eq(%w[spec/x_spec.rb])
      expect(stale("spec/x_spec.rb" => "9" * 64, "spec/y_spec.rb" => "8" * 64)).to eq(%w[spec/x_spec.rb spec/y_spec.rb])
    end

    it "counts a changed spec file that recorded no test as zero seconds" do
      inv = described_class.new(map: map, root: root, included: %w[lib/a.rb],
                                spec_files: %w[spec/x_spec.rb spec/y_spec.rb spec/v_spec.rb])
      snap = base.merge("files" => files.merge("spec/v_spec.rb" => "a" * 64))
      after = snap.merge("files" => snap["files"].merge("spec/v_spec.rb" => "b" * 64, "spec/x_spec.rb" => "9" * 64))
      expect(inv.stale_specs(snap, after)).to eq(%w[spec/x_spec.rb spec/v_spec.rb])
      durations["./spec/x_spec.rb[1:1]"] = 5.01
      expect(inv.stale_specs(snap, after)).to eq(:full)
    end

    it "stays partial at a total of exactly one second when only half of it is stale" do
      durations.replace("./spec/x_spec.rb[1:1]" => 0.5, "./spec/y_spec.rb[1:1]" => 0.5)
      expect(stale("spec/x_spec.rb" => "9" * 64)).to eq(%w[spec/x_spec.rb])
    end

    it "gives the stale share of the recorded time, 0 when none was recorded" do
      durations.replace("./spec/x_spec.rb[1:1]" => 3, "./spec/y_spec.rb[1:1]" => 1)
      expect(invalidation.share(%w[spec/x_spec.rb])).to eq(0.75)
      expect(invalidation.share([])).to eq(0.0)
      durations.clear
      expect(invalidation.share(%w[spec/x_spec.rb])).to eq(0.0)
    end

    it "goes full when no duration was recorded" do
      durations.clear
      expect(stale("spec/x_spec.rb" => "9" * 64)).to eq(:full)
    end
  end

  context "when the project root is spelled through a symlink" do
    around do |example|
      Dir.mktmpdir do |dir|
        @real = File.realpath(dir)
        FileUtils.mkdir_p(File.join(@real, "lib"))
        File.write(File.join(@real, "lib", "a.rb"), "1\n")
        File.symlink(@real, File.join(@real, "..", "link-#{File.basename(@real)}"))
        @link = File.join(File.dirname(@real), "link-#{File.basename(@real)}")
        example.run
      ensure
        FileUtils.rm_f(@link) if @link
      end
    end

    let(:invalidation) do
      described_class.new(map: map, root: @link, included: %w[lib/a.rb], spec_files: %w[spec/x_spec.rb spec/z_spec.rb])
    end
    let(:a_src) { File.join(@real, "lib", "a.rb") }

    it "matches the map's real paths" do
      expect(stale("lib/a.rb" => "9" * 64)).to eq(%w[spec/z_spec.rb spec/x_spec.rb])
    end

    context "when the file was loaded before coverage started" do
      let(:extra) { { preloaded: [File.join(@real, "lib", "a.rb")] } }

      it("goes full through the symlinked spelling") { expect(stale("lib/a.rb" => "9" * 64)).to eq(:full) }
    end
  end

  describe "when RSpec selects examples from spec/examples.txt" do
    let(:edited) { base.merge("files" => files.merge("spec/x_spec.rb" => "9" * 64)) }

    def with_status_file(flag)
      described_class.new(map: map, root: root, included: %w[lib/a.rb lib/b.rb],
                          spec_files: %w[spec/x_spec.rb spec/y_spec.rb spec/z_spec.rb spec/w_spec.rb],
                          status_file: flag)
    end

    it "reuses the map otherwise" do
      expect(with_status_file(false).stale_specs(base, edited)).to eq(["spec/x_spec.rb"])
    end

    it "is :full" do
      expect(with_status_file(true).stale_specs(base, edited)).to eq(:full)
    end
  end
end
