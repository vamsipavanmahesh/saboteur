# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

# The parent-side verdict code of Runner, called directly with canned child
# events, so no fork or timing decides the result.
RSpec.describe Saboteur::Execution::Runner, "parent-side outcomes" do
  let(:job_class) { described_class::Job }
  let(:mutation) { double("mutation", digest: "0123456789abcdef") }
  let(:subject_double) { double("subject", start_byte: 4, file_source: "src") }

  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  def runner(**options)
    described_class.new(integration: nil, reevaluator: nil, log_dir: File.join(@dir, "logs"), **options)
  end

  def job(mutation: self.mutation, subject: subject_double, ids: %w[a b], timeout: 1.234)
    job_class.new(subject:, text: "t", test_ids: ids, timeout:, mutation:, log_path: File.join(@dir, "child.log"))
  end

  def exit_status(command)
    system(command)
    Process.last_status
  end

  describe "#initialize" do
    it "keeps the crash log next to the logs dir unless one is given" do
      expect(runner.instance_variable_get(:@crash_log))
        .to eq(File.join(@dir, Saboteur::CrashReport::LOG_NAME))
      expect(runner(crash_log: "/x/crash.log").instance_variable_get(:@crash_log)).to eq("/x/crash.log")
    end
  end

  describe "#log_tail" do
    let(:path) { File.join(@dir, "child.log") }

    it "is nil for a missing or empty log" do
      expect(runner.send(:log_tail, path)).to be_nil
      File.write(path, "")
      expect(runner.send(:log_tail, path)).to be_nil
    end

    it "returns a short log whole, scrubbed and stripped" do
      external = Encoding.default_external
      Encoding.default_external = Encoding::UTF_8
      File.binwrite(path, "  hi\xFF there \n")
      expect(runner.send(:log_tail, path)).to eq("hi\uFFFD there")
    ensure
      Encoding.default_external = external
    end

    it "returns only the last bytes of a long log" do
      File.write(path, ("a" * 7) + ("b" * described_class::LOG_TAIL_BYTES))
      expect(runner.send(:log_tail, path)).to eq("b" * described_class::LOG_TAIL_BYTES)
    end
  end

  describe "#describe" do
    it "names a missing status, a signal and a plain exit" do
      expect(runner.send(:describe, nil)).to eq("exited")
      expect(runner.send(:describe, exit_status("exit 3"))).to eq("exited with status 3")
      expect(runner.send(:describe, exit_status("exit 0"))).to eq("exited with status 0")
      pid = spawn("sleep 5")
      Process.kill("TERM", pid)
      Process.wait(pid)
      expect(runner.send(:describe, Process.last_status)).to eq("killed by signal 15")
    end
  end

  describe "#classify" do
    let(:status) { exit_status("exit 3") }

    def classify(events, log: nil, run_job: job)
      File.write(run_job.log_path, log) if log
      runner.send(:classify, events, status, 0.5, run_job).message
    end

    it "words a child that died with no result or error" do
      expect(classify([{ "event" => "started" }])).to eq("child exited with status 3 during tests")
      expect(classify([])).to eq("child exited with status 3 before tests")
    end

    it "marks an error that came before the tests started" do
      error = { "event" => "error", "message" => "boom" }
      expect(classify([error])).to eq("boom (before tests)")
      expect(classify([{ "event" => "started" }, error])).to eq("boom")
    end

    it "appends the log tail on its own line" do
      expect(classify([], log: "last words\n")).to eq("child exited with status 3 before tests\nlast words")
    end
  end

  describe "#classify_result" do
    def result(run_result, ids: %w[a b], verbose: false)
      runner.send(:classify_result, run_result, 0.5, ids, verbose_failure: verbose)
    end

    it "treats a test that called exit as a kill" do
      outcome = result({ "exited" => 1 })
      expect([outcome.status, outcome.message]).to eq([:killed, "test called exit"])
    end

    it "names up to three failed tests that were not requested" do
      outcome = result({ "failed" => %w[a w x y z], "executed" => %w[a] })
      expect([outcome.status, outcome.message]).to eq([:error, "failed tests not requested: w, x, y"])
    end

    it "calls a failed suite with no failed test a suite-level failure" do
      outcome = result({ "passed" => false, "executed" => %w[a b] })
      expect([outcome.status, outcome.message, outcome.executed_ids])
        .to eq([:killed, "suite-level failure", %w[a b]])
    end

    it "reports a passing run that executed other tests" do
      outcome = result({ "passed" => true, "executed" => %w[a] })
      expect([outcome.status, outcome.message]).to eq([:error, "executed 1 of 2 requested tests"])
    end
  end

  describe "#killed_outcome and #failure_message" do
    def killed(run_result, verbose: false)
      runner.send(:classify_result, run_result.merge("passed" => false), 0.5, %w[a b], verbose_failure: verbose)
    end

    let(:base) { { "failed" => %w[a b], "executed" => %w[a b] } }

    it "keeps a true observation on a kill and never reports false (#1311)" do
      expect(killed(base.merge("value_differed" => true)).value_differed).to be(true)
      expect(killed(base.merge("value_differed" => false)).value_differed).to be_nil
      expect(killed(base).value_differed).to be_nil
    end

    it "uses the first failed test for the message and the kill cause" do
      outcome = killed(base.merge("failure_messages" => { "a" => "ma", "b" => "mb" },
                                  "failure_classes" => { "a" => "NoMethodError",
                                                         "b" => "RSpec::Mocks::MockExpectationError" }))
      expect([outcome.message, outcome.kill_cause, outcome.failed_ids]).to eq(["ma", "NoMethodError", %w[a b]])
    end

    it "works when the child sent no messages or classes" do
      outcome = killed(base)
      expect([outcome.message, outcome.kill_cause]).to eq([nil, nil])
      expect(killed(base, verbose: true).message).to be_nil
    end

    it "prefers the full details for a neutral check and falls back to the message" do
      messages = { "failure_messages" => { "a" => "short" } }
      expect(killed(base.merge(messages), verbose: true).message).to eq("short")
      details = messages.merge("failure_details" => { "a" => "long" })
      expect(killed(base.merge(details), verbose: true).message).to eq("long")
      expect(killed(base.merge(details)).message).to eq("short")
    end
  end

  describe "#classify_events" do
    let(:survived) { { "passed" => true, "executed" => %w[a b], "replacement_called" => false } }

    def events(run_result, *extra, run_job: job)
      runner.send(:classify_events, run_result, extra, 0.5, run_job)
    end

    def captures(site = "c.rb:3") = { "event" => "captures", "site" => site }

    it "finds the captures event by its name and words the unreachable verdict" do
      outcome = events(survived, { "event" => "started" }, captures)
      expect([outcome.status, outcome.message]).to eq(
        [:unreachable, "a Method object captured before re-evaluation still calls the original " \
                       "(captured definition at c.rb:3)"]
      )
    end

    it "stays survived unless every condition holds" do
      expect(events(survived).status).to eq(:survived)
      expect(events(survived, { "event" => "started" }).status).to eq(:survived)
      expect(events(survived, captures, run_job: job(mutation: nil)).status).to eq(:survived)
      expect(events(survived.merge("replacement_called" => true), captures).status).to eq(:survived)
      expect(events(survived.merge("replacement_called" => nil), captures).status).to eq(:survived)
      expect(events(survived.merge("failed" => %w[a], "passed" => false), captures).status).to eq(:killed)
    end

    it "only converts a mutant run that the tests overwrote" do
      overwritten = { "event" => "overwritten", "site" => "o.rb:7" }
      outcome = events(survived.merge("replacement_called" => true), overwritten)
      expect([outcome.status, outcome.message]).to eq(
        [:unreachable, "the tests (or their hooks) replaced the definition while they ran (o.rb:7), " \
                       "so this mutant never ran"]
      )
      expect(events(survived.merge("replacement_called" => true), overwritten,
                    run_job: job(mutation: nil)).status).to eq(:survived)
    end
  end

  describe "#outcome_for" do
    let(:stopped) do
      Struct.new(:stopped_by, :runtime, :detail, :leftover_pids, :payload, :exit_status)
    end

    it "words a timeout with the rounded limit and keeps the leftover pids" do
      result = stopped.new(:timeout, 1.5, nil, [11, 12])
      outcome = runner.send(:outcome_for, result, job)
      expect([outcome.status, outcome.message, outcome.leftover_pids]).to eq([:timeout, "exceeded 1.23 s", [11, 12]])
    end

    it "passes a memory stop's detail through" do
      outcome = runner.send(:outcome_for, stopped.new(:memory, 1.5, "over 5 MB", []), job)
      expect([outcome.status, outcome.message]).to eq([:resource_limit, "over 5 MB"])
    end
  end

  describe "the mutant digest and the probes" do
    it "has a digest only for a mutant run on a subject with a start byte" do
      expect(runner.send(:culprit_digest, job)).to eq("0123456789abcdef")
      expect(mutation).to have_received(:digest).with(subject_start: 4, original_source: "src")
      expect(runner.send(:culprit_digest, job(mutation: nil))).to be_nil
      expect(runner.send(:culprit_digest, job(subject: Object.new))).to be_nil
    end

    it "gives the canary the subject and the digest" do
      canary = double("canary", probe!: nil)
      runner(canary:).send(:check_tree_still_there, job)
      expect(canary).to have_received(:probe!).with(subject: subject_double, digest: "0123456789abcdef")
    end

    it "words a vanished log and carries the digest" do
      run_job = job
      message = "the child log #{run_job.log_path} vanished mid-run - the mutant that just ran, " \
                "0123456789abcdef, is the likely cause: a mutant's tests may have hit saboteur's files"
      expect { runner.send(:check_log_still_there, run_job) }
        .to raise_error(described_class::LogVanished) { |e|
          expect(e.message).to eq(message)
          expect(e.culprit_digest).to eq("0123456789abcdef")
        }
    end

    it "words a log that cannot be opened" do
      run_job = job_class.new(subject: nil, text: "", test_ids: [], timeout: 1,
                              log_path: File.join(@dir, "no", "child.log"))
      reason = begin
        File.open(run_job.log_path, "w")
      rescue SystemCallError => e
        e.message
      end
      expect { runner.send(:open_log, run_job) }.to raise_error(
        Saboteur::Error, "cannot open the child log #{run_job.log_path} (Errno::ENOENT: #{reason})"
      )
    end
  end
end
