# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::PartialMerge do
  def map(lines: {}, tests: [], **rest)
    Saboteur::Selection::CoverageMap.new(lines: lines, tests: tests, **rest)
  end

  let(:base) do
    map(lines: { "/a.rb" => { 1 => %w[./spec/x_spec.rb[1:1] ./spec/y_spec.rb[1:1]], 2 => %w[./spec/x_spec.rb[1:1]] } },
        methods: { "/a.rb" => { 1 => %w[./spec/x_spec.rb[1:1]], 2 => %w[./spec/y_spec.rb[1:1]] } },
        branches: { "/a.rb" => { "1:0-2:0" => %w[./spec/x_spec.rb[1:1] ./spec/y_spec.rb[1:1]] } },
        tests: %w[./spec/x_spec.rb[1:1] ./spec/y_spec.rb[1:1]],
        durations: { "./spec/x_spec.rb[1:1]" => 1.0, "./spec/y_spec.rb[1:1]" => 2.0 },
        load_lines: { "/boot.rb" => [1] }, load_methods: { "/boot.rb" => [3] }, loaded_files: ["/base.rb"],
        preloaded: ["/pre.rb"], build_seconds: 10.0)
  end
  let(:fresh) do
    map(lines: { "/a.rb" => { 3 => %w[./spec/x_spec.rb[1:1] ./spec/x_spec.rb[1:2]] } },
        tests: %w[./spec/x_spec.rb[1:1] ./spec/x_spec.rb[1:2]],
        durations: { "./spec/x_spec.rb[1:1]" => 0.5, "./spec/x_spec.rb[1:2]" => 0.25 },
        load_lines: { "/boot.rb" => [2] }, loaded_files: ["/new.rb"], build_seconds: 4.0)
  end
  let(:merged) { described_class.call(base, fresh, %w[spec/x_spec.rb]) }

  it "drops every trace of the rerun spec file's old tests and adds the fresh ones" do
    expect(merged.tests).to eq(%w[./spec/y_spec.rb[1:1] ./spec/x_spec.rb[1:1] ./spec/x_spec.rb[1:2]])
    expect(merged.lines["/a.rb"]).to eq(1 => %w[./spec/y_spec.rb[1:1]],
                                        3 => %w[./spec/x_spec.rb[1:1] ./spec/x_spec.rb[1:2]])
    expect(merged.methods).to eq("/a.rb" => { 2 => %w[./spec/y_spec.rb[1:1]] })
    expect(merged.branches["/a.rb"]).to eq("1:0-2:0" => %w[./spec/y_spec.rb[1:1]])
  end

  it "keeps the other files' durations and takes the fresh ones for the rerun file" do
    expect(merged.durations).to eq("./spec/y_spec.rb[1:1]" => 2.0, "./spec/x_spec.rb[1:1]" => 0.5,
                                   "./spec/x_spec.rb[1:2]" => 0.25)
  end

  it "unions load-time evidence, loaded files and preloaded files, and sums the build time" do
    expect(merged.load_lines).to eq("/boot.rb" => [1, 2])
    expect(merged.load_methods).to eq("/boot.rb" => [3])
    expect(merged.loaded_files).to eq(%w[/base.rb /new.rb])
    expect(merged.preloaded.to_a).to eq(["/pre.rb"])
    expect(merged.build_seconds).to eq(14.0)
  end

  it "leaves the base map untouched" do
    merged
    expect(base.tests.size).to eq(2)
    expect(base.lines["/a.rb"][1].size).to eq(2)
  end

  it "replaces nothing when no spec file is rerun and the fresh map is empty" do
    result = described_class.call(base, map, [])
    expect(result.tests).to eq(base.tests)
    expect(result.lines).to eq(base.lines)
  end

  it "leaves no key for a file or line that no test covers any more, so it reads as no evidence" do
    hit = { 1 => %w[./spec/a_spec.rb[1:1]] }
    only = map(lines: { "/f.rb" => hit }, methods: { "/f.rb" => hit },
               tests: %w[./spec/a_spec.rb[1:1] ./spec/b_spec.rb[1:1]],
               durations: { "./spec/a_spec.rb[1:1]" => 1.0, "./spec/b_spec.rb[1:1]" => 1.0 })
    rerun = map(lines: { "/other.rb" => { 1 => %w[./spec/a_spec.rb[1:1]] } }, tests: %w[./spec/a_spec.rb[1:1]])
    result = described_class.call(only, rerun, %w[spec/a_spec.rb])
    expect(result.lines.keys).to eq(["/other.rb"])
    expect(result.methods).to eq({})
    invalidation = Saboteur::Engine::PartialInvalidation.new(
      map: result, root: "/", included: %w[f.rb], spec_files: %w[spec/a_spec.rb spec/b_spec.rb]
    )
    before = { "format" => 1, "root" => "r", "runtime" => "t", "settings" => "s", "files" => { "f.rb" => "1" * 64 } }
    after = before.merge("files" => { "f.rb" => "2" * 64 })
    expect(invalidation.stale_specs(before, after)).to eq(:full)
  end
end
