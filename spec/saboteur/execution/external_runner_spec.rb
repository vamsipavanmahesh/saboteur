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
    runner.run(subject: subject, text: subject.source, test_ids: [], timeout: timeout,
               mutation: mutation == :real ? mutation_for(subject) : nil)
    [runner, subject]
  end

  around do |example|
    Dir.mktmpdir { |dir| @dir = File.realpath(dir) and example.run }
  end

  it "reports survived when the command exits 0 with the mutant applied" do
    runner, subject = run_in(@dir, "true")
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    expect([outcome.status, outcome.executed_ids]).to eq([:survived, ["(test command)"]])
  end

  it "reports killed with the command as the killer when it exits non-zero" do
    runner, subject = run_in(@dir, "false")
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    expect([outcome.status, outcome.failed_ids]).to eq([:killed, ["(test command)"]])
  end

  it "writes the mutated file for the command and restores the original bytes" do
    runner, subject = run_in(@dir, "grep -q 'n < 0' calc.rb")
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    # grep found the mutant text, so the exit is 0: the write happened.
    expect(outcome.status).to eq(:survived)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  it "restores the original file even when the command times out" do
    runner, subject = run_in(@dir, "sleep 30")
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 0.2,
                         mutation: mutation_for(subject))
    expect(outcome.status).to eq(:timeout)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  it "runs the unchanged tree for the neutral check and does not write" do
    runner, subject = run_in(@dir, "grep -q 'n >= 0' calc.rb")
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5, mutation: nil)
    expect(outcome.status).to eq(:survived)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end

  # The command runs through the shell, so an unknown command exits
  # non-zero and reads as a kill - say so instead of pretending to detect it.
  it "reads an unspawnable command's shell failure as a kill" do
    runner, subject = run_in(@dir, "definitely-not-a-command-xyz")
    outcome = runner.run(subject: subject, text: subject.source, test_ids: [], timeout: 5,
                         mutation: mutation_for(subject))
    expect(outcome.status).to eq(:killed)
    expect(File.read(File.join(@dir, "calc.rb"))).to eq(source)
  end
end
