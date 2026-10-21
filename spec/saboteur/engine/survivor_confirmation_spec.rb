# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::SurvivorConfirmation, "#1063" do
  let(:file) { "/app/lib/thing.rb" }
  let(:edit) { double("edit") }
  let(:mutation) { double("mutation", edits: [edit], operator: "literal_string", digest: "abc123") }
  let(:subject_double) do
    double("subject", id: "Thing#call", file: file, singleton: false, sig_source: nil, start_byte: 0,
                      file_source: "def call; end", source: "def call; :ok end",
                      coverage_lines: [10], coverage_lines_for: [10])
  end
  let(:tids) { (1..10).map { |n| "./spec/thing_#{n}_spec.rb[1:1]" } }
  let(:durations) { tids.each_with_index.to_h { |id, i| [id, (i + 1) * 1.0] } }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { file => { 10 => tids } }, tests: tids, durations: durations)
  end
  let(:config) do
    { "timeout_factor" => 3.0, "timeout_min" => 5.0, "baseline_timeout" => 300.0,
      "confirmation_budget" => 300.0 }
  end
  let(:runner) { double("runner") }
  let(:scheduler) { double("scheduler", runner: runner, confirmation_prefix: nil) }
  let(:diagnostics) { double("diagnostics", inform: nil, warn: nil) }
  let(:ignore_list) { double("ignore_list", accepts?: false) }
  let(:budget_exceeded) { -> { false } }
  before do
    allow(map).to receive(:tests_for_branches).and_return(nil)
  end

  let(:confirmation) do
    described_class.new(config: config, map: map, scheduler: scheduler, diagnostics: diagnostics,
                        budget_exceeded: budget_exceeded)
  end

  def survivor(executed: ["./spec/thing_1_spec.rb[1:1]"], runtime: 1.0, covered_by: tids)
    Saboteur::MutantResult.new(subject: subject_double, mutation: mutation, status: :survived,
                               mutated_source: "def call; end", runtime: runtime, covered_by: covered_by,
                               executed: executed)
  end

  def outcome(status:, runtime: 0.5, failed: [], message: "ok", executed: [])
    double("outcome", status: status, runtime: runtime, failed_ids: failed, message: message,
                      executed_ids: executed, kill_cause: status == :killed ? "assertion" : nil)
  end

  # The mutant run gets the mutated source; the VerdictCheck re-run gets the
  # unchanged method. Dispatch the runner double on that text.
  def stub_mutant_and_unchanged(mutant_outcome, unchanged_outcome)
    allow(runner).to receive(:run) do |args|
      args[:text] == "def call; end" ? mutant_outcome : unchanged_outcome
    end
  end

  it "reclassifies a survivor as killed when an unrun covering spec fails, naming the spec" do
    result = survivor
    stub_mutant_and_unchanged(outcome(status: :killed, failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"], message: "1 failed"),
                              outcome(status: :survived))

    confirmed = confirmation.call([result], ignore_list: ignore_list).first

    expect(confirmed.status).to eq(:killed)
    expect(confirmed.confirmation).to eq("confirmed")
    expect(confirmed.killed_by).to eq(["./spec/thing_3_spec.rb[1:1]"])
    expect(confirmed.executed).to include("./spec/thing_1_spec.rb[1:1]", "./spec/thing_3_spec.rb[1:1]")
    expect(diagnostics).to have_received(:inform).with(%r{killed on confirmation by \./spec/thing_3_spec})
  end

  it "records a standing confirmation kill with the full covering test set, evicting the cached survivor" do
    cache = double("cache", record: nil)
    caching = described_class.new(config: config, map: map, scheduler: scheduler, diagnostics: diagnostics,
                                  budget_exceeded: budget_exceeded, cache: cache)
    stub_mutant_and_unchanged(outcome(status: :killed, failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"]),
                              outcome(status: :survived))

    caching.call([survivor(executed: tids.first(2))], ignore_list: ignore_list)

    expect(cache).to have_received(:record) do |recorded|
      expect(recorded.status).to eq(:killed)
      expect(recorded.covered_by).to match_array(tids)
    end
  end

  it "records nothing for a rejected or unchecked kill" do
    cache = double("cache", record: nil)
    caching = described_class.new(config: config, map: map, scheduler: scheduler, diagnostics: diagnostics,
                                  budget_exceeded: budget_exceeded, cache: cache)
    stub_mutant_and_unchanged(outcome(status: :killed, failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"]),
                              outcome(status: :killed, failed: ["./spec/thing_3_spec.rb[1:1]"]))

    caching.call([survivor], ignore_list: ignore_list)

    expect(cache).not_to have_received(:record)
  end

  it "rejects the kill when the killing spec also fails with the method unchanged" do
    stub_mutant_and_unchanged(outcome(status: :killed, failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"], message: "1 failed"),
                              outcome(status: :killed, failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      message: "fails unchanged"))

    confirmed = confirmation.call([survivor], ignore_list: ignore_list).first

    expect(confirmed.status).to eq(:error)
    expect(confirmed.rejected_kill?).to be(true)
    expect(confirmed.reason).to include("also fails with the method unchanged")
  end

  it "leaves the kill unverified and uncredited when the budgets stop the unchanged check" do
    tight = config.merge("confirmation_budget" => 1.0)
    tight_confirmation = described_class.new(config: tight, map: map, scheduler: scheduler,
                                             diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    stub_mutant_and_unchanged(outcome(status: :killed, failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"], runtime: 1.5),
                              outcome(status: :survived))

    confirmed = tight_confirmation.call([survivor], ignore_list: ignore_list).first

    expect(confirmed.status).to eq(:unverified)
    expect(confirmed.reason).to include("confirmation budget is spent")
  end

  it "keeps the survivor status when every unrun covering spec passes" do
    allow(runner).to receive(:run).and_return(outcome(status: :survived))

    confirmed = confirmation.call([survivor], ignore_list: ignore_list).first

    expect(confirmed.status).to eq(:survived)
    expect(confirmed.confirmation).to eq("confirmed")
  end

  it "runs only covering specs the mutant did not already execute, fastest first, capped at eight" do
    allow(runner).to receive(:run).and_return(outcome(status: :survived))

    confirmation.call([survivor(executed: tids.first(2))], ignore_list: ignore_list)

    expect(runner).to have_received(:run) do |args|
      expect(args[:test_ids]).to eq(tids[2..9])
    end
  end

  it "orders over-eight unrun covering specs by recorded runtime, unrecorded last, capped at eight" do
    unordered = [tids[4], tids[9], tids[2], tids[7], tids[0], tids[6], tids[1], tids[8], tids[3], tids[5]]
    durations = { tids[0] => 50.0, tids[1] => 10.0, tids[2] => 90.0, tids[3] => 30.0, tids[4] => 70.0,
                  tids[5] => 20.0, tids[6] => 80.0, tids[7] => 40.0, tids[8] => 60.0 }
    mixed = Saboteur::Selection::CoverageMap.new(lines: { file => { 10 => tids } }, tests: tids,
                                                 durations: durations)
    allow(mixed).to receive(:tests_for_branches).and_return(nil)
    allow(mixed).to receive(:tests_for_edit).and_return(unordered)
    mixed_confirmation = described_class.new(config: config, map: mixed, scheduler: scheduler,
                                             diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    captured = []
    allow(runner).to receive(:run) { |args| captured << args and outcome(status: :survived) }

    mixed_confirmation.call([survivor(executed: [tids[0]])], ignore_list: ignore_list)

    expect(captured.length).to eq(1)
    expect(captured.first[:test_ids])
      .to eq([tids[1], tids[5], tids[3], tids[7], tids[8], tids[4], tids[6], tids[2]])
  end

  it "leaves a survivor untouched when no covering spec remains unrun" do
    allow(runner).to receive(:run)
    result = survivor(executed: tids)

    expect(confirmation.call([result], ignore_list: ignore_list).first).to equal(result)
    expect(runner).not_to have_received(:run)
  end

  it "never confirms a survivor the ignore list accepts" do
    allow(runner).to receive(:run)
    accepting = double("ignore_list", accepts?: true)
    result = survivor

    expect(confirmation.call([result], ignore_list: accepting).first).to equal(result)
    expect(runner).not_to have_received(:run)
  end

  it "labels survivors unconfirmed once the confirmation budget is spent" do
    allow(runner).to receive(:run).and_return(outcome(status: :survived, runtime: 250.0))
    tight = config.merge("confirmation_budget" => 250.0)
    tight_confirmation = described_class.new(config: tight, map: map, scheduler: scheduler,
                                             diagnostics: diagnostics, budget_exceeded: budget_exceeded)

    confirmed = tight_confirmation.call([survivor, survivor], ignore_list: ignore_list)

    expect(confirmed.map(&:confirmation)).to eq(["confirmed", "unconfirmed(the confirmation budget is spent)"])
  end

  it "labels a survivor unconfirmed when its confirmation run ends in a timeout" do
    allow(runner).to receive(:run).and_return(outcome(status: :timeout, message: "exceeded 5s"))

    confirmed = confirmation.call([survivor], ignore_list: ignore_list).first

    expect(confirmed.status).to eq(:survived)
    expect(confirmed.confirmation).to eq("unconfirmed(the confirmation run timeout: exceeded 5s)")
  end

  it "labels survivors unconfirmed when the run's max-duration budget is already spent" do
    spent = described_class.new(config: config, map: map, scheduler: scheduler, diagnostics: diagnostics,
                                budget_exceeded: -> { true })
    allow(runner).to receive(:run)

    confirmed = spent.call([survivor], ignore_list: ignore_list).first

    expect(confirmed.confirmation).to eq("unconfirmed(the --max-duration budget is spent)")
    expect(runner).not_to have_received(:run)
  end

  it "warns that only the survivors reached before an early stop were covered" do
    allow(runner).to receive(:run).and_return(outcome(status: :survived))
    early_stop = double("early_stop", reason: "fail_fast")

    confirmation.call([survivor], ignore_list: ignore_list, early_stop: early_stop)

    expect(diagnostics).to have_received(:warn).with(/stopped early \(fail_fast\)/)
  end

  it "falls back to the mutant's first-run runtime when the map has no durations" do
    bare_map = Saboteur::Selection::CoverageMap.new(lines: { file => { 10 => tids } }, tests: tids)
    allow(bare_map).to receive(:tests_for_branches).and_return(nil)
    bare = described_class.new(config: config, map: bare_map, scheduler: scheduler, diagnostics: diagnostics,
                               budget_exceeded: budget_exceeded)
    allow(runner).to receive(:run).and_return(outcome(status: :survived))

    bare.call([survivor(runtime: 2.0)], ignore_list: ignore_list)

    expect(runner).to have_received(:run) do |args|
      expect(args[:timeout]).to eq(6.0)
    end
  end

  it "summarizes the outcome, so the pass is never silent" do
    allow(runner).to receive(:run).and_return(outcome(status: :survived))

    confirmation.call([survivor], ignore_list: ignore_list)

    expect(diagnostics).to have_received(:inform).with(/survivor confirmation: 1 confirmed/)
  end

  it "passes non-survivors through without confirming them, asking the ignore list about each" do
    killed = Saboteur::MutantResult.new(subject: subject_double, mutation: mutation, status: :killed,
                                        mutated_source: "def call; end")
    allow(runner).to receive(:run).and_return(outcome(status: :survived))

    surv = survivor
    confirmed = confirmation.call([killed, surv], ignore_list: ignore_list)

    expect(confirmed.first).to equal(killed)
    expect(runner).to have_received(:run).once
    expect(ignore_list).to have_received(:accepts?).with(surv)
  end

  it "does not warn about an early stop when there is nothing to confirm" do
    killed = Saboteur::MutantResult.new(subject: subject_double, mutation: mutation, status: :killed,
                                        mutated_source: "def call; end")

    confirmation.call([killed], ignore_list: ignore_list, early_stop: double("early_stop", reason: "fail_fast"))

    expect(diagnostics).not_to have_received(:warn)
  end

  it "names the early-stop reason in the full warning" do
    allow(runner).to receive(:run).and_return(outcome(status: :survived))

    confirmation.call([survivor], ignore_list: ignore_list, early_stop: double("early_stop", reason: "fail_fast"))

    expect(diagnostics).to have_received(:warn).with(
      "survivor confirmation covers only the survivors reached before the run stopped early (fail_fast)"
    )
  end

  it "marks later survivors unconfirmed when a confirmation run overshoots the budget" do
    allow(runner).to receive(:run).and_return(outcome(status: :survived, runtime: 150.0))
    tight = described_class.new(config: config.merge("confirmation_budget" => 100.0), map: map,
                                scheduler: scheduler, diagnostics: diagnostics, budget_exceeded: budget_exceeded)

    confirmed = tight.call([survivor, survivor], ignore_list: ignore_list)

    expect(confirmed.map(&:confirmation)).to eq(["confirmed", "unconfirmed(the confirmation budget is spent)"])
  end

  it "does not spend budget on a confirmation run with no recorded runtime" do
    allow(runner).to receive(:run).and_return(outcome(status: :survived, runtime: nil),
                                              outcome(status: :survived, runtime: 1.0))
    tight = described_class.new(config: config.merge("confirmation_budget" => 0.5), map: map,
                                scheduler: scheduler, diagnostics: diagnostics, budget_exceeded: budget_exceeded)

    confirmed = tight.call([survivor, survivor, survivor], ignore_list: ignore_list)

    expect(confirmed.map(&:confirmation)).to eq(["confirmed", "confirmed",
                                                 "unconfirmed(the confirmation budget is spent)"])
  end

  it "runs the unrun covering specs fastest first" do
    durations = { tids[0] => 60.0, tids[1] => 100.0, tids[2] => 50.0, tids[3] => 10.0,
                  tids[4] => 90.0, tids[5] => 20.0, tids[6] => 80.0, tids[7] => 30.0,
                  tids[8] => 70.0, tids[9] => 40.0 }
    slow = Saboteur::Selection::CoverageMap.new(lines: { file => { 10 => tids } }, tests: tids,
                                                durations: durations)
    allow(slow).to receive(:tests_for_branches).and_return(nil)
    slow_confirmation = described_class.new(config: config, map: slow, scheduler: scheduler,
                                            diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    captured = []
    allow(runner).to receive(:run) { |args| captured << args and outcome(status: :survived) }

    slow_confirmation.call([survivor(executed: tids.first(2))], ignore_list: ignore_list)

    expect(captured.length).to eq(1)
    expect(captured.first[:test_ids]).to eq([tids[3], tids[5], tids[7], tids[9], tids[2], tids[8], tids[6], tids[4]])
  end

  it "hands the runner the subject, mutated source, tests, timeout, mutation and eval prefix" do
    allow(runner).to receive(:run).and_return(outcome(status: :survived))

    confirmation.call([survivor(executed: tids.first(2))], ignore_list: ignore_list)

    expect(runner).to have_received(:run).with(subject: subject_double, text: "def call; end",
                                               test_ids: tids[2..9],
                                               timeout: 3.0 * map.recorded_runtime(tids[2..9]),
                                               mutation: mutation, eval_prefix: nil)
    expect(scheduler).to have_received(:confirmation_prefix).with(subject_double)
  end

  it "intersects line and branch evidence for the covering tests" do
    allow(map).to receive(:tests_for_branches).and_return(tids[0..3])
    captured = []
    allow(runner).to receive(:run) { |args| captured << args and outcome(status: :survived) }

    confirmation.call([survivor], ignore_list: ignore_list)

    expect(captured.length).to eq(1)
    expect(captured.first[:test_ids]).to eq(tids[1..3])
    expect(subject_double).to have_received(:coverage_lines_for).with(edit)
    expect(map).to have_received(:tests_for_branches).with(subject_double, mutation.edits)
  end

  it "treats a survivor without an executed list through its covering tests" do
    captured = []
    allow(runner).to receive(:run) { |args| captured << args and outcome(status: :survived) }

    confirmation.call([survivor(executed: nil, covered_by: tids.first(4))], ignore_list: ignore_list)

    expect(captured.length).to eq(1)
    expect(captured.first[:test_ids]).to eq(tids[4..9])
  end

  it "falls back to the suite's mean runtime when neither the tests nor the mutant ran timed" do
    sparse = Saboteur::Selection::CoverageMap.new(lines: { file => { 10 => tids } }, tests: tids,
                                                  durations: { tids[8] => 9.0, tids[9] => 10.0 })
    allow(sparse).to receive(:tests_for_branches).and_return(nil)
    sparse_confirmation = described_class.new(config: config, map: sparse, scheduler: scheduler,
                                              diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    captured = []
    allow(runner).to receive(:run) { |args| captured << args and outcome(status: :survived) }

    sparse_confirmation.call([survivor(runtime: nil)], ignore_list: ignore_list)

    expect(captured.length).to eq(1)
    expect(captured.first[:timeout]).to eq(3.0 * 9.5)
  end

  it "floors the confirmation timeout at timeout_min" do
    quick = Saboteur::Selection::CoverageMap.new(lines: { file => { 10 => tids } }, tests: tids,
                                                 durations: { tids[8] => 0.1 })
    allow(quick).to receive(:tests_for_branches).and_return(nil)
    quick_confirmation = described_class.new(config: config, map: quick, scheduler: scheduler,
                                             diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    captured = []
    allow(runner).to receive(:run) { |args| captured << args and outcome(status: :survived) }

    quick_confirmation.call([survivor(executed: tids.first(8))], ignore_list: ignore_list)

    expect(captured.length).to eq(1)
    expect(captured.first[:timeout]).to eq(5.0)
  end

  it "uses the baseline timeout when no runtime evidence exists at all" do
    bare = Saboteur::Selection::CoverageMap.new(lines: { file => { 10 => tids } }, tests: tids)
    allow(bare).to receive(:tests_for_branches).and_return(nil)
    bare_confirmation = described_class.new(config: config, map: bare, scheduler: scheduler,
                                            diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    captured = []
    allow(runner).to receive(:run) { |args| captured << args and outcome(status: :survived) }

    bare_confirmation.call([survivor(runtime: nil)], ignore_list: ignore_list)

    expect(captured.length).to eq(1)
    expect(captured.first[:timeout]).to eq(300.0)
  end

  it "carries the confirmation outcome's message, tests, cause and summed runtime onto the kill" do
    stub_mutant_and_unchanged(outcome(status: :killed, runtime: 0.5, message: "1 failed",
                                      failed: ["./spec/thing_3_spec.rb[1:1]", "./spec/thing_5_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"]),
                              outcome(status: :survived))

    confirmed = confirmation.call([survivor], ignore_list: ignore_list).first

    expect(confirmed.reason).to eq("1 failed")
    expect(confirmed.kill_cause).to eq("assertion")
    expect(confirmed.runtime).to eq(1.5)
    expect(confirmed.covered_by).to eq(tids[1..8])
    expect(diagnostics).to have_received(:inform).with(
      "Thing#call literal_string abc123: killed on confirmation by ./spec/thing_3_spec.rb[1:1]"
    )
  end

  it "treats missing runtimes and executions as empty in the kill" do
    stub_mutant_and_unchanged(outcome(status: :killed, runtime: nil,
                                      failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"]),
                              outcome(status: :survived))

    confirmed = confirmation.call([survivor(runtime: nil, executed: nil, covered_by: tids.first(4))],
                                  ignore_list: ignore_list).first

    expect(confirmed.status).to eq(:killed)
    expect(confirmed.runtime).to eq(0)
    expect(confirmed.executed).to eq(["./spec/thing_3_spec.rb[1:1]"])
  end

  it "checks the kill against the unchanged method with the baseline timeout" do
    stub_mutant_and_unchanged(outcome(status: :killed, failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"]),
                              outcome(status: :survived))

    confirmation.call([survivor], ignore_list: ignore_list)

    expect(runner).to have_received(:run).with(subject: subject_double, text: "def call; :ok end",
                                               test_ids: ["./spec/thing_2_spec.rb[1:1]",
                                                          "./spec/thing_3_spec.rb[1:1]"],
                                               timeout: 300.0, eval_prefix: nil)
    expect(scheduler).to have_received(:confirmation_prefix).with(subject_double).twice
  end

  it "caches the standing kill marked confirmed" do
    cache = double("cache", record: nil)
    caching = described_class.new(config: config, map: map, scheduler: scheduler, diagnostics: diagnostics,
                                  budget_exceeded: budget_exceeded, cache: cache)
    stub_mutant_and_unchanged(outcome(status: :killed, failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"]),
                              outcome(status: :survived))

    caching.call([survivor], ignore_list: ignore_list)

    expect(cache).to have_received(:record) do |recorded|
      expect(recorded.confirmation).to eq("confirmed")
    end
  end

  it "leaves the kill unverified when the max-duration budget stops the unchanged check" do
    calls = 0
    flip = -> { (calls += 1) > 1 }
    flipping = described_class.new(config: config, map: map, scheduler: scheduler, diagnostics: diagnostics,
                                   budget_exceeded: flip)
    stub_mutant_and_unchanged(outcome(status: :killed, failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"]),
                              outcome(status: :survived))

    confirmed = flipping.call([survivor], ignore_list: ignore_list).first

    expect(confirmed.status).to eq(:unverified)
  end

  it "runs the unchanged check while any confirmation budget remains" do
    roomy = described_class.new(config: config.merge("confirmation_budget" => 1.5), map: map,
                                scheduler: scheduler, diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    stub_mutant_and_unchanged(outcome(status: :killed, runtime: 0.5,
                                      failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"]),
                              outcome(status: :survived))

    confirmed = roomy.call([survivor], ignore_list: ignore_list).first

    expect(confirmed.status).to eq(:killed)
  end

  it "stops the unchanged check at exactly zero budget" do
    exact = described_class.new(config: config.merge("confirmation_budget" => 0.5), map: map,
                                scheduler: scheduler, diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    stub_mutant_and_unchanged(outcome(status: :killed, runtime: 0.5,
                                      failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"]),
                              outcome(status: :survived))

    confirmed = exact.call([survivor], ignore_list: ignore_list).first

    expect(confirmed.status).to eq(:unverified)
  end

  it "spends confirmation budget on the unchanged re-run" do
    tight = described_class.new(config: config.merge("confirmation_budget" => 1.0), map: map,
                                scheduler: scheduler, diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    stub_mutant_and_unchanged(outcome(status: :killed, runtime: 0.5,
                                      failed: ["./spec/thing_3_spec.rb[1:1]"],
                                      executed: ["./spec/thing_3_spec.rb[1:1]"]),
                              outcome(status: :survived, runtime: 0.5))

    confirmed = tight.call([survivor, survivor], ignore_list: ignore_list)

    expect(confirmed.map(&:confirmation)).to eq(["confirmed", "unconfirmed(the confirmation budget is spent)"])
  end

  it "treats an untimed unchanged re-run as free" do
    tight = described_class.new(config: config.merge("confirmation_budget" => 0.5), map: map,
                                scheduler: scheduler, diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    later = [outcome(status: :survived, runtime: 1.0)]
    allow(runner).to receive(:run) do |args|
      args[:text] == "def call; :ok end" ? outcome(status: :survived, runtime: nil) : later.shift
    end
    first = outcome(status: :killed, runtime: nil, failed: ["./spec/thing_3_spec.rb[1:1]"],
                    executed: ["./spec/thing_3_spec.rb[1:1]"])
    later.unshift(first)

    confirmed = tight.call([survivor, survivor], ignore_list: ignore_list)

    expect(confirmed.map(&:confirmation)).to eq(%w[confirmed confirmed])
  end

  it "does not refund budget on an untimed unchanged re-run" do
    tight = described_class.new(config: config.merge("confirmation_budget" => 0.5), map: map,
                                scheduler: scheduler, diagnostics: diagnostics, budget_exceeded: budget_exceeded)
    runs = [outcome(status: :killed, runtime: nil, failed: ["./spec/thing_3_spec.rb[1:1]"],
                    executed: ["./spec/thing_3_spec.rb[1:1]"]),
            outcome(status: :survived, runtime: 1.0)]
    allow(runner).to receive(:run) do |args|
      args[:text] == "def call; :ok end" ? outcome(status: :survived, runtime: nil) : runs.shift
    end

    confirmed = tight.call([survivor, survivor, survivor], ignore_list: ignore_list)

    expect(confirmed.map(&:confirmation)).to eq(["confirmed", "confirmed",
                                                 "unconfirmed(the confirmation budget is spent)"])
  end

  it "stays silent when no survivor could be marked" do
    allow(runner).to receive(:run)

    confirmation.call([survivor(executed: tids)], ignore_list: ignore_list)

    expect(diagnostics).not_to have_received(:inform)
  end

  it "joins the summary marks with commas" do
    allow(runner).to receive(:run).and_return(outcome(status: :survived, runtime: 250.0))
    tight = described_class.new(config: config.merge("confirmation_budget" => 250.0), map: map,
                                scheduler: scheduler, diagnostics: diagnostics, budget_exceeded: budget_exceeded)

    tight.call([survivor, survivor], ignore_list: ignore_list)

    expect(diagnostics).to have_received(:inform).with(
      "survivor confirmation: 1 confirmed, 1 unconfirmed(the confirmation budget is spent)"
    )
  end

  describe Saboteur::MutantResult, "#with_confirmation" do
    it "carries reason, runtime, kill cause, reused and rejected-kill flags onto the copy" do
      original = Saboteur::MutantResult.new(subject: subject_double, mutation: mutation, status: :survived,
                                            mutated_source: "def call; end", reason: "why", runtime: 1.5,
                                            killed_by: ["t"], covered_by: ["t"], kill_cause: "assertion",
                                            executed: ["t"], rejected_kill: true, reused: true)

      copy = original.with_confirmation("confirmed")

      expect([copy.reason, copy.runtime, copy.kill_cause, copy.reused?, copy.rejected_kill?,
              copy.confirmation])
        .to eq(["why", 1.5, "assertion", true, true, "confirmed"])
    end
  end

  describe Saboteur::Engine, "#confirm_survivors gating" do
    around do |example|
      Dir.mktmpdir { |dir| @root = File.realpath(dir) and example.run }
    end

    it "returns results untouched when partial_coverage is off" do
      eng = described_class.new(Saboteur::Config.new({ "partial_coverage" => "off" }, root: @root),
                                err: StringIO.new)
      results = [double("result")]

      expect(Saboteur::Engine::SurvivorConfirmation).not_to receive(:new)
      expect(eng.send(:confirm_survivors, results, double("scheduler", map: nil), nil, nil)).to equal(results)
    end

    it "runs the confirmation pass when CoveragePartial.use? holds" do
      eng = described_class.new(Saboteur::Config.new({ "partial_coverage" => "use" }, root: @root),
                                err: StringIO.new)
      results = [double("result")]
      pass = double("pass")
      scheduler = double("scheduler", map: nil)

      expect(Saboteur::Engine::SurvivorConfirmation).to receive(:new)
        .with(config: anything, map: nil, scheduler: scheduler, diagnostics: anything,
              budget_exceeded: anything, cache: nil)
        .and_return(pass)
      expect(pass).to receive(:call).with(results, ignore_list: nil, early_stop: nil).and_return(:done)
      expect(eng.send(:confirm_survivors, results, scheduler, nil, nil)).to eq(:done)
    end
  end

  describe Saboteur::Engine::CoveragePartial do
    it "gates on use plus cache plus unscoped plus single-part" do
      base = { "partial_coverage" => "use", "cache" => true, "tests" => [] }
      expect(described_class.use?(base, 1)).to be(true)
      expect(described_class.use?(base.merge("partial_coverage" => "shadow"), 1)).to be(false)
      expect(described_class.use?(base.merge("cache" => false), 1)).to be(false)
      expect(described_class.use?(base.merge("tests" => ["spec/a_spec.rb"]), 1)).to be(false)
      expect(described_class.use?(base, 2)).to be(false)
    end
  end
end
