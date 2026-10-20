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
    expect(compare(map)).to eq(result: :match, match: true, total: 0, extra: 0, gained: 0, differences: [])
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

  describe "when the partial map only credits more tests" do
    let(:full) { map(lines: { "/a.rb" => { 1 => %w[t1] } }) }

    it "is a superset, and counts each extra credit on a line the full map also credits" do
      result = compare(map(lines: { "/a.rb" => { 1 => %w[t1 t2 t3] } }, tests: %w[t1 t2 t3]),
                       map(lines: full.lines, tests: %w[t1 t2 t3]))
      expect(result).to include(result: :superset, match: false, total: 1, extra: 2, gained: 0)
      expect(result[:differences]).to eq([{ kind: "lines", name: "/a.rb" }])
      expect(result.keys).to eq(%i[result match total extra gained differences])
    end

    it "is a mismatch for a credit on a line the full map calls uncovered, counted apart" do
      result = compare(map(lines: { "/a.rb" => { 1 => %w[t1], 2 => %w[t1 t2] } }), full)
      expect(result).to include(result: :mismatch, total: 1, extra: 0, gained: 2)
    end

    it "is a mismatch for a credit in a file the full map has no credit in" do
      partial = map(lines: { "/a.rb" => { 1 => %w[t1] }, "/b.rb" => { 1 => %w[t1] } })
      result = compare(partial, full)
      expect(result).to include(result: :mismatch, extra: 0, gained: 1, total: 1)
      expect(result[:differences]).to eq([{ kind: "lines", name: "/b.rb" }])
    end

    it "is a mismatch when it also lacks a credit the full map has" do
      result = compare(map(lines: { "/a.rb" => { 1 => %w[t2] } }), full)
      expect(result).to include(result: :mismatch, extra: 1, gained: 0)
    end

    it "is a mismatch when one file only gained credits and another lost one" do
      both = { "/a.rb" => { 1 => %w[t1] }, "/b.rb" => { 1 => %w[t1] } }
      result = compare(map(lines: { "/a.rb" => { 1 => %w[t1 t2] } }), map(lines: both))
      expect(result).to include(result: :mismatch, extra: 1, gained: 0, total: 2)
    end

    it "counts gained credits in methods and branches the same way" do
      result = compare(map(methods: { "/a.rb" => { 1 => %w[t1] } }, branches: { "/a.rb" => { "s" => %w[t1 t2] } }),
                       map(branches: { "/a.rb" => { "s" => %w[t1] } }))
      expect(result).to include(result: :mismatch, extra: 1, gained: 1, total: 2)
    end

    it "lists differences sorted by kind then name, with exactly kind and name" do
      partial = map(lines: { "/b.rb" => { 1 => %w[t1] }, "/a.rb" => { 1 => %w[t1 t2], 2 => %w[t1] } },
                    methods: { "/a.rb" => { 1 => %w[t1] } })
      names = compare(partial, map(lines: { "/a.rb" => { 1 => %w[t1 t2] } }))[:differences]
      expect(names).to eq([{ kind: "lines", name: "/a.rb" }, { kind: "lines", name: "/b.rb" },
                           { kind: "methods", name: "/a.rb" }])
    end

    it "is a mismatch when a whole line is missing" do
      result = compare(map(lines: { "/a.rb" => {} }), full)
      expect(result).to include(result: :mismatch, extra: 0, gained: 0)
    end

    it "is a mismatch when the load-time lines differ, even only by extra ones" do
      with = ->(lines) { map(lines: full.lines, load_lines: { "/b.rb" => lines }) }
      result = compare(with.call([1, 2]), with.call([1]))
      expect(result).to include(result: :mismatch, total: 1, differences: [{ kind: "load", name: "/b.rb" }])
    end

    it "lists each difference with its kind first, then its name" do
      result = compare(map(lines: full.lines, load_lines: { "/b.rb" => [1] }),
                       map(lines: full.lines, load_lines: { "/b.rb" => [2] }))
      expect(result[:differences].map(&:keys)).to eq([%i[kind name]])
    end

    it "matches when the same load-time lines were seen" do
      same = map(lines: full.lines, load_lines: { "/b.rb" => [2, 1] })
      expect(compare(same, map(lines: full.lines, load_lines: { "/b.rb" => [1, 2] }))[:result]).to eq(:match)
    end

    it "is a mismatch when a test lost a file it touched, even if it gained another" do
      partial = map(lines: { "/b.rb" => { 1 => %w[t1] } })
      full = map(lines: { "/a.rb" => { 1 => %w[t1] } })
      expect(compare(partial, full)[:result]).to eq(:mismatch)
    end

    it "is a mismatch when the set of tests differs" do
      expect(compare(map(lines: full.lines, tests: %w[t1 t2 t3]), full)[:result]).to eq(:mismatch)
    end

    it "is a mismatch when the unobserved or boot files differ, even by extra ones" do
      expect(compare(map(lines: full.lines, loaded_files: ["/u.rb"]), full)[:result]).to eq(:mismatch)
    end
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
    expect(result[:total]).to eq(60)
    expect(result[:differences].size).to eq(50)
    expect(result[:differences]).to eq(result[:differences].sort_by { |item| [item[:kind], item[:name]] })
  end

  it "lists the differences sorted by kind and then name" do
    partial = map(lines: { "/z.rb" => { 1 => %w[t1] }, "/b.rb" => { 1 => %w[t1] } }, tests: %w[t1 t3],
                  loaded_files: ["/u.rb"])
    full = map(lines: {}, tests: %w[t1])
    expect(compare(partial, full)[:differences].map { |item| item.values_at(:kind, :name) }).to eq(
      [["deps", "(unobserved files)"], ["lines", "/b.rb"], ["lines", "/z.rb"],
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
