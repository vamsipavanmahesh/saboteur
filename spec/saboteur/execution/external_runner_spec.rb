# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::ExternalRunner do
  let(:source) do
    <<~RUBY
      class Calc
        def positive?(n)
          n >= 0
        end
      end
    RUBY
  end

  def subject_in(dir)
    path = File.join(dir, "calc.rb")
    File.write(path, source)
    Saboteur::SubjectFinder.new.call(path).subjects.first
  end

  def mutation_for(subject)
    at = subject.file_source.index(">=")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2,
                                              replacement: "<")
    Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits: [edit],
                                           coarse: false)
  end

  def run_in(dir, command, timeout: 5, mutation: :real)
    subject = subject_in(dir)
    runner = described_class.new(command: command, root: dir)
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: timeout,
                         mutation: mutation == :real ? mutation_for(subject) : nil)
    [outcome, runner, subject]
  end

  # Functional proof the group is gone: a reaped zombie still answers
  # kill(0), so watch the descendant's tick file stop growing instead.
  def expect_ticks_stopped(path)
    size = File.exist?(path) ? File.size(path) : 0
    sleep 0.5
    expect(File.exist?(path) ? File.size(path) : 0).to eq(size)
  end

  around do |example|
    Dir.mktmpdir { |dir| @dir = File.realpath(dir) and example.run }
  end

  it "reports survived when the command exits 0 with the mutant applied" do
    outcome, = run_in(@dir, "true")
    expect([outcome.status, outcome.executed_ids]).to eq([:survived, ["(test command)"]])
  end

  it "reports killed with the command as the killer when it exits non-zero" do
    outcome, = run_in(@dir, "false")
    expect([outcome.status, outcome.failed_ids]).to eq([:killed, ["(test command)"]])
  end

  it "lets the command see the mutant and never touches the real file" do
    outcome, = run_in(@dir, "grep -q 'n < 0' calc.rb")
    # grep found the mutant text, so the write happened in the copy.
    expect(outcome.status).to eq(:survived)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  it "leaves the real file alone when the command times out" do
    outcome, = run_in(@dir, "sleep 30", timeout: 0.2)
    expect(outcome.status).to eq(:timeout)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  it "runs the unchanged copy for the neutral check and does not write" do
    outcome, = run_in(@dir, "grep -q 'n >= 0' calc.rb", mutation: nil)
    expect(outcome.status).to eq(:survived)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  # The shell's "cannot run it" exits are setup errors, not kills (#305):
  # the suite did not run.
  it "reads 127 (command not found) as an error, not a kill" do
    outcome, = run_in(@dir, "definitely-not-a-command-xyz")
    expect([outcome.status, outcome.executed_ids]).to eq([:error, []])
  end

  # An error verdict keeps bounded context for the report (#305 DevRel):
  # what the shell said, capped at the capture limit.
  it "carries the command's own output on setup errors" do
    outcome, = run_in(@dir, "definitely-not-a-command-xyz")
    expect(outcome.message).to include("exit 127 - the shell could not run the command")
    expect(outcome.message).to include("definitely-not-a-command-xyz")
    expect(outcome.message.bytesize).to be < described_class::OUTPUT_LIMIT + 200
  end

  it "reads 126 (cannot execute) as an error" do
    outcome, = run_in(@dir, "exit 126")
    expect(outcome.status).to eq(:error)
  end

  it "reads a command killed by a signal as an error" do
    outcome, = run_in(@dir, "kill -TERM $$")
    expect(outcome.status).to eq(:error)
  end

  # Architect probe, taken further by QA/DevRel: a command that destroys
  # the source inside the copy must not poison ANY later execution - every
  # run starts from a pristine copy (#305).
  it "gives every execution a pristine copy after a destructive command" do
    subject = subject_in(@dir)
    runner = described_class.new(command: "rm calc.rb && mkdir calc.rb", root: @dir)
    first = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                       mutation: mutation_for(subject))
    second = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                        mutation: mutation_for(subject))
    # Both runs honestly report the command's exit; the second mutant is
    # written into a fresh copy, not onto the first run's debris.
    expect([first.status, second.status]).to eq(%i[survived survived])
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  # The neutral check must see pristine bytes even right after a mutant
  # (#305 QA): kills are never checked against themselves.
  it "runs the neutral check on unchanged bytes after a mutant" do
    subject = subject_in(@dir)
    runner = described_class.new(command: "grep -q 'n >= 0' calc.rb", root: @dir)
    mutant = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                        mutation: mutation_for(subject))
    neutral = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5, mutation: nil)
    # The command detects the mutant (kill), and the neutral run passes
    # because the fresh copy carries the original bytes again.
    expect([mutant.status, neutral.status]).to eq(%i[killed survived])
  end

  # Mutants in one file must not leak into another file's runs (#305 QA).
  it "keeps mutants in one file out of another file's executions" do
    subject = subject_in(@dir)
    File.write(File.join(@dir, "other.rb"), "OTHER = 1
")
    runner = described_class.new(command: "grep -q 'OTHER = 1' other.rb", root: @dir)
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    expect(outcome.status).to eq(:survived)
  end

  # cp_r keeps symlinks; a link escaping the tree would let a write land
  # in the real tree, so the runner refuses it (#305 QA).
  it "refuses a symlink that escapes the tree" do
    subject_in(@dir)
    outside = File.join(@dir, "..", "outside-#{Process.pid}.rb")
    File.write(outside, "x = 1
")
    File.symlink(outside, File.join(@dir, "linked.rb"))
    runner = described_class.new(command: "true", root: @dir)
    expect { runner.preflight! }.to raise_error(Saboteur::Error, /links outside itself: linked\.rb/)
  ensure
    File.unlink(outside) if outside && File.exist?(outside)
  end

  it "dereferences a symlink that stays inside the tree" do
    subject = subject_in(@dir)
    File.symlink("calc.rb", File.join(@dir, "alias.rb"))
    runner = described_class.new(command: "grep -q 'class Calc' alias.rb", root: @dir)
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    # The alias is real content in the copy; the real files are untouched
    # and the real alias is still a symlink.
    expect(outcome.status).to eq(:survived)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
    expect(File.symlink?(File.join(@dir, "alias.rb"))).to be(true)
  end

  # Architect probe: a background write landing after the verdict must not
  # reach the real tree (#305).
  it "contains a background write that lands after the run" do
    command = "(sleep 0.3; printf LATE > calc.rb) & exit 0"
    outcome, = run_in(@dir, command)
    expect(outcome.status).to eq(:survived)
    sleep 0.6
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  # Architect probe: SIGINT must take the whole process group down (#305).
  # The ready file is a handshake: the command has started before the
  # interrupt lands (Principal: no startup race).
  it "kills the process group when the run is interrupted" do
    subject_in(@dir)
    ticks = File.join(@dir, "ticks")
    command = "touch #{@dir}/ready; (while :; do echo t >> #{ticks}; sleep 0.1; done) & wait"
    runner = described_class.new(command: command, root: @dir)
    subject = Saboteur::SubjectFinder.new.call(File.join(@dir, "calc.rb")).subjects.first
    thread = Thread.new do
      runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 30,
                 mutation: mutation_for(subject))
    end
    100.times do
      break if File.exist?(File.join(@dir, "ready"))

      sleep 0.05
    end
    thread.raise(Interrupt)
    expect { thread.join }.to raise_error(Interrupt)
    expect_ticks_stopped(ticks)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  it "kills background descendants that outlive the command" do
    subject_in(@dir)
    ticks = File.join(@dir, "ticks")
    command = "(while :; do echo t >> #{ticks}; sleep 0.1; done) & exit 0"
    runner = described_class.new(command: command, root: @dir)
    subject = Saboteur::SubjectFinder.new.call(File.join(@dir, "calc.rb")).subjects.first
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    expect(outcome.status).to eq(:survived)
    expect_ticks_stopped(ticks)
  end

  it "passes the recursion marker down to the command's environment" do
    outcome, = run_in(@dir, "test \"$SABOTEUR_EXTERNAL_CHILD\" = 1")
    expect(outcome.status).to eq(:survived)
  end

  # The disposable copy must not leak (merger review, #305): close removes
  # it after normal runs and after errors, and stays idempotent.
  describe "#close" do
    it "removes the copy after a normal run" do
      outcome, runner, = run_in(@dir, "true")
      expect(outcome.status).to eq(:survived)
      copy = runner.instance_variable_get(:@copy_root)
      expect(Dir.exist?(copy)).to be(true)
      runner.close
      expect(Dir.exist?(copy)).to be(false)
      expect { runner.close }.not_to raise_error
    end

    it "removes the copy after a mutant run errors" do
      subject = subject_in(@dir)
      runner = described_class.new(command: "rm calc.rb && mkdir calc.rb", root: @dir)
      runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                 mutation: mutation_for(subject))
      outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                           mutation: mutation_for(subject))
      expect(outcome.status).to eq(:survived) # fresh copy: the first run's debris is gone
      copy = runner.instance_variable_get(:@copy_root)
      runner.close
      expect(Dir.exist?(copy)).to be(false)
    end
  end

  describe "#preflight!" do
    it "passes when the command exits 0 on the unchanged copy" do
      subject_in(@dir)
      runner = described_class.new(command: "true", root: @dir)
      expect(runner.preflight!).to be(true)
    end

    it "fails the run with the exit status and the command's own output" do
      subject_in(@dir)
      runner = described_class.new(command: "echo oops >&2; exit 1", root: @dir)
      expect { runner.preflight! }
        .to raise_error(Saboteur::Error, /unchanged tree \(exit 1\):.*oops/m)
    end

    it "explains a 127 as the shell being unable to run the command" do
      subject_in(@dir)
      runner = described_class.new(command: "definitely-not-a-command-xyz", root: @dir)
      expect { runner.preflight! }
        .to raise_error(Saboteur::Error, /exit 127 - the shell could not run the command/)
    end

    it "honors the given timeout, so the run budget caps it (#305 QA)" do
      subject_in(@dir)
      runner = described_class.new(command: "sleep 30", root: @dir)
      expect { runner.preflight!(timeout: 0.2) }.to raise_error(Saboteur::Error, /timed out/)
    end

    it "bounds the captured output" do
      subject_in(@dir)
      runner = described_class.new(command: "yes X | head -c 200000; exit 1", root: @dir)
      expect { runner.preflight! }.to raise_error(Saboteur::Error) do |error|
        expect(error.message.bytesize).to be < described_class::OUTPUT_LIMIT + 200
      end
    end
  end
end
