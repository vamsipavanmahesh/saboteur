# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::ShadowComparison do
  def map(**given)
    args = { lines: { "/a.rb" => { 1 => %w[t1 t2] } }, tests: %w[t1 t2] }.merge(given)
    Saboteur::Selection::CoverageMap.new(**args)
  end

  def compare(partial, full = map, **options)
    described_class.call(partial, full, **options)
  end

  it "matches identical maps" do
    expect(compare(map)).to eq(match: true, total: 0, differences: [])
  end

  it "ignores durations, build time, id order and entries with no test" do
    other = map(lines: { "/a.rb" => { 1 => %w[t2 t1], 2 => [] }, "/dark.rb" => {} }, tests: %w[t2 t1],
                durations: { "t1" => 9.0 }, build_seconds: 3.0)
    expect(compare(other, map(durations: { "t1" => 1.0 }, build_seconds: 1.0))[:match]).to be(true)
  end

  it "names a line that a test hit in one map only" do
    result = compare(map(lines: { "/a.rb" => { 1 => %w[t1] } }))
    expect(result[:match]).to be(false)
    expect(result[:differences]).to include(kind: "lines", name: "/a.rb")
  end

  it "names a method, a branch arm and a load-time difference" do
    base = map(methods: { "/a.rb" => { 1 => %w[t1] } }, branches: { "/a.rb" => { "s" => %w[t1] } },
               load_lines: { "/b.rb" => [1] })
    changed = map(methods: { "/a.rb" => { 1 => %w[t2] } }, branches: { "/a.rb" => { "s" => %w[t2] } },
                  load_lines: { "/b.rb" => [2] })
    kinds = compare(changed, base)[:differences].map { |item| item[:kind] }
    expect(kinds).to include("methods", "branches", "load")
  end

  it "treats a load-time method like a load-time line" do
    result = compare(map(load_methods: { "/b.rb" => [4] }))
    expect(result[:differences]).to include(kind: "load", name: "/b.rb")
  end

  it "names a differing set of test ids" do
    result = compare(map(tests: %w[t1 t2 t3]))
    expect(result[:differences]).to include(kind: "tests", name: "the set of test ids")
  end

  it "reports a different dependency set even when the evidence of the tests matches" do
    partial = map(lines: { "/a.rb" => { 1 => %w[t1] } }, tests: %w[t1 t2])
    full = map(lines: { "/a.rb" => { 1 => %w[t1] } }, tests: %w[t1 t2], loaded_files: ["/u.rb"])
    expect(compare(partial, full)[:differences]).to eq([{ kind: "deps", name: "(unobserved files)" }])
  end

  it "uses the fallback files for the unobserved set on both sides" do
    result = compare(map, map, fallback_files: ["/missing.rb"])
    expect(result[:match]).to be(true)
  end

  it "reports a changed boot file set" do
    result = compare(map(load_lines: { "/b.rb" => [1] }), map(load_lines: { "/b.rb" => [1], "/c.rb" => [2] }))
    expect(result[:differences]).to include(kind: "deps", name: "(boot files)")
  end

  it "counts every difference but lists at most MAX_DIFFERENCES, sorted" do
    many = (1..60).to_h { |index| ["/f#{format('%02d', index)}.rb", { 1 => %w[t1] }] }
    result = compare(map(lines: many), map(lines: {}))
    expect(result[:total]).to be > 60
    expect(result[:differences].size).to eq(50)
    expect(result[:differences]).to eq(result[:differences].sort_by { |item| [item[:kind], item[:name]] })
  end

  it "lists the differences sorted by kind and then name" do
    partial = map(lines: { "/z.rb" => { 1 => %w[t1] }, "/b.rb" => { 1 => %w[t1] } }, tests: %w[t1 t3],
                  loaded_files: ["/u.rb"])
    full = map(lines: {}, tests: %w[t1])
    expect(compare(partial, full)[:differences].map { |item| item.values_at(:kind, :name) }).to eq(
      [["deps", "(unobserved files)"], ["deps", "t1"], ["lines", "/b.rb"], ["lines", "/z.rb"],
       ["tests", "the set of test ids"]]
    )
  end

  it "does not count an empty load-time entry as evidence" do
    expect(compare(map(load_methods: { "/b.rb" => [] }), map)[:match]).to be(true)
  end

  it "ignores the order a file's tests and the loaded files were recorded in" do
    partial = map(lines: { "/a.rb" => { 1 => %w[t1] }, "/b.rb" => { 1 => %w[t1] } }, tests: %w[t1],
                  loaded_files: %w[/u.rb /v.rb])
    full = map(lines: { "/b.rb" => { 1 => %w[t1] }, "/a.rb" => { 1 => %w[t1] } }, tests: %w[t1],
               loaded_files: %w[/v.rb /u.rb])
    expect(compare(partial, full)[:match]).to be(true)
  end

  it "counts a file once however many kinds of evidence name it" do
    partial = map(lines: { "/a.rb" => { 1 => %w[t1] } }, methods: { "/a.rb" => { 1 => %w[t1] } }, tests: %w[t1])
    full = map(lines: { "/a.rb" => { 1 => %w[t1] } }, tests: %w[t1])
    expect(compare(partial, full)[:differences]).to eq([{ kind: "methods", name: "/a.rb" }])
  end

  it "sees a fallback file that only one map has evidence for" do
    partial = map(lines: { "/f.rb" => { 1 => %w[t1] } }, tests: %w[t1])
    full = map(lines: {}, tests: %w[t1])
    expect(compare(partial, full,
                   fallback_files: ["/f.rb"])[:differences]).to include(kind: "deps", name: "(unobserved files)")
  end
end
