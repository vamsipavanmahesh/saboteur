# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::ShadowRun do
  def map(lines:, tests:, **rest)
    Saboteur::Selection::CoverageMap.new(lines: lines, tests: tests, durations: tests.to_h { |id| [id, 1.0] }, **rest)
  end

  let(:x_id) { "./spec/x_spec.rb[1:1]" }
  let(:y_id) { "./spec/y_spec.rb[1:1]" }
  let(:base_map) { map(lines: { "/p/a.rb" => { 1 => [x_id] }, "/p/b.rb" => { 1 => [y_id] } }, tests: [x_id, y_id]) }
  let(:full_map) { base_map }
  let(:files) { { "a.rb" => "1" * 64, "b.rb" => "2" * 64, "spec/x_spec.rb" => "3" * 64, "spec/y_spec.rb" => "4" * 64 } }
  let(:base) do
    { "format" => 2, "root" => "r", "runtime" => "t", "settings" => "s", "seed" => 7, "map_key" => "k" * 64,
      "files" => files }
  end
  let(:own) { { "seed" => 99, "map_key" => "z" * 64 } }
  let(:current) { base.merge(own, "files" => files.merge("spec/x_spec.rb" => "9" * 64)) }
  let(:fresh) { map(lines: { "/p/a.rb" => { 1 => [x_id] } }, tests: [x_id]) }
  let(:calls) { [] }
  let(:rerun) { ->(specs, seed) { (calls << [specs, seed]) && fresh } }
  let(:invalidation) do
    Saboteur::Engine::PartialInvalidation.new(map: base_map, root: "/p", included: %w[a.rb b.rb],
                                              spec_files: %w[spec/x_spec.rb spec/y_spec.rb])
  end

  def run(**given)
    described_class.call(base: base, base_map: base_map, current: current, full_map: full_map,
                         invalidation: invalidation, fallback_files: [], rerun: rerun,
                         clean: ->(value) { "<#{value}>" }, **given)
  end

  it "reruns the stale spec files with the base snapshot's seed and reports a match" do
    report = run
    expect(calls).to eq([[%w[spec/x_spec.rb], 7]])
    expect(report).to include("result" => "match", "stale" => ["<spec/x_spec.rb>"], "stale_share" => 0.5,
                              "threshold" => 0.5, "total" => 0, "differences" => [], "base_map" => "k" * 64)
  end

  it "reports a superset, with its extra credits, when the rerun only credits more tests" do
    more = map(lines: { "/p/a.rb" => { 1 => [x_id, y_id] } }, tests: [x_id])
    report = run(rerun: ->(_specs, _seed) { more })
    expect(report).to include("result" => "superset")
    expect(report["extra_credits"]).to be > 0
  end

  it "reports a mismatch with its differences, cleaned" do
    wrong = map(lines: { "/p/a.rb" => { 2 => [x_id] } }, tests: [x_id])
    report = run(rerun: ->(_specs, _seed) { wrong })
    expect(report["result"]).to eq("mismatch")
    expect(report["total"]).to be > 0
    expect(report["differences"]).to include("kind" => "<lines>", "name" => "</p/a.rb>")
  end

  it "skips, without a rerun, when a full rebuild is needed, and still carries the threshold" do
    report = run(current: base.merge(own, "files" => files.merge("a.rb" => "9" * 64, "other.yml" => "1" * 64)))
    expect(calls).to eq([])
    expect(report).to eq("threshold" => 0.5, "base_map" => "k" * 64, "result" => "skipped",
                         "reason" => "a full rebuild is needed")
  end

  it "compares the base map itself when no spec file is stale, without a rerun" do
    report = run(current: base.merge(own))
    expect(calls).to eq([])
    expect(report).to include("result" => "match", "stale" => [], "stale_share" => 0.0)
  end

  it "asks the invalidation about base then current, and compares with the fallback files" do
    allow(invalidation).to receive(:stale_specs).and_call_original
    allow(Saboteur::Engine::ShadowComparison).to receive(:call).and_call_original

    run(fallback_files: %w[/p/a.rb])

    expect(invalidation).to have_received(:stale_specs).with(base, current)
    expect(Saboteur::Engine::ShadowComparison).to have_received(:call)
      .with(anything, full_map, fallback_files: %w[/p/a.rb])
  end

  # Code that runs once per process, such as a memoized singleton, is credited
  # to whichever test reaches it first, so a rerun of only the stale specs can
  # change who gets the credit (#46).
  describe "a line that runs once per process" do
    let(:base_map) do
      map(lines: { "/p/a.rb" => { 1 => [lead] } }, tests: [x_id, y_id])
    end

    context "when the stale spec held the credit and no longer reaches the line" do
      let(:lead) { x_id }
      let(:full_map) { map(lines: { "/p/a.rb" => { 1 => [y_id] } }, tests: [x_id, y_id]) }
      let(:fresh) { map(lines: {}, tests: [x_id]) }

      it "is a mismatch: the next test to reach it would stay uncredited" do
        report = run
        expect(report).to include("result" => "mismatch", "extra_credits" => 0, "total" => 1)
        expect(report["differences"]).to eq([{ "kind" => "<lines>", "name" => "</p/a.rb>" }])
      end
    end

    context "when a stale spec now reaches a line another test held" do
      let(:lead) { y_id }
      let(:full_map) { base_map }
      let(:fresh) { map(lines: { "/p/a.rb" => { 1 => [x_id] } }, tests: [x_id]) }

      it "is a superset with the extra credit counted, never a match" do
        report = run
        expect(report).to include("result" => "superset", "extra_credits" => 1, "total" => 1)
        expect(report["differences"]).to eq([{ "kind" => "<lines>", "name" => "</p/a.rb>" }])
      end
    end
  end
end
