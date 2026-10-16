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

  # The group leader's pid is its pgid: wait until no member of the group
  # remains, or fail.
  def expect_group_dead(pgid)
    50.times do
      begin
        Process.kill(0, -pgid)
      rescue Errno::ESRCH
        return
      end
      sleep 0.1
    end
    raise "process group #{pgid} still alive"
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

  it "reads 126 (cannot execute) as an error" do
    outcome, = run_in(@dir, "exit 126")
    expect(outcome.status).to eq(:error)
  end

  it "reads a command killed by a signal as an error" do
    outcome, = run_in(@dir, "kill -TERM $$")
    expect(outcome.status).to eq(:error)
  end

  # Architect probe: a command that destroys the source inside the copy
  # must not poison later mutants, and the real tree stays intact (#305).
  it "contains a command that removes the source and mkdirs its name" do
    subject = subject_in(@dir)
    runner = described_class.new(command: "rm calc.rb && mkdir calc.rb", root: @dir)
    first = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                       mutation: mutation_for(subject))
    second = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                        mutation: mutation_for(subject))
    expect(first.status).to eq(:survived) # the command exited 0; honest verdict
    expect(second.status).to eq(:error) # the copy's calc.rb is now a directory
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
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
  it "kills the process group when the run is interrupted" do
    subject_in(@dir)
    runner = described_class.new(command: "echo $$ > #{@dir}/pgid; sleep 30", root: @dir)
    subject = Saboteur::SubjectFinder.new.call(File.join(@dir, "calc.rb")).subjects.first
    thread = Thread.new do
      runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 30,
                 mutation: mutation_for(subject))
    end
    sleep 0.5
    thread.raise(Interrupt)
    expect { thread.join }.to raise_error(Interrupt)
    expect_group_dead(File.read(File.join(@dir, "pgid")).to_i)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  it "kills background descendants that outlive the command" do
    subject_in(@dir)
    runner = described_class.new(command: "echo $$ > #{@dir}/pgid; sleep 30 & exit 0", root: @dir)
    subject = Saboteur::SubjectFinder.new.call(File.join(@dir, "calc.rb")).subjects.first
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    expect(outcome.status).to eq(:survived)
    expect_group_dead(File.read(File.join(@dir, "pgid")).to_i)
  end

  # Principal: a test command that itself invokes saboteur must not start a
  # nested run (#305).
  it "refuses to start inside another external test command" do
    ENV[described_class::CHILD_MARKER] = "1"
    expect { described_class.new(command: "true", root: @dir) }
      .to raise_error(Saboteur::Error, /nested run/)
  ensure
    ENV.delete(described_class::CHILD_MARKER)
  end

  it "passes the recursion marker down to the command's environment" do
    outcome, = run_in(@dir, "test \"$SABOTEUR_EXTERNAL_CHILD\" = 1")
    expect(outcome.status).to eq(:survived)
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

    it "bounds the captured output" do
      subject_in(@dir)
      runner = described_class.new(command: "yes X | head -c 200000; exit 1", root: @dir)
      expect { runner.preflight! }.to raise_error(Saboteur::Error) do |error|
        expect(error.message.bytesize).to be < described_class::OUTPUT_LIMIT + 200
      end
    end
  end
end
