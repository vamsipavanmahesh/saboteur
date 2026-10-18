# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# #641: under --test-command there is no coverage map, so a subject the
# command never loads reads as ordinary survivors. Name the gap per subject:
# mutants ran, nothing killed, nothing errored, at least one survivor. A
# heuristic line only - no score or exit-code change.
RSpec.describe "--test-command survivor gap hint (#641)" do
  def terminal_output(report)
    output = StringIO.new
    Saboteur::Reporter::Terminal.new(output).call(report)
    output.string
  end

  def report_with(statuses, test_command: "bundle exec ruby -Itest test/person_test.rb")
    results = statuses.map { |status| result_for(status) }
    Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1,
                         root: File.dirname(person_subject.file), test_command:)
  end

  it "names a subject with mutants, no kills, no errors, and at least one survivor" do
    output = terminal_output(report_with(%i[survived survived]))
    expect(output).to include("Person#adult?: no coverage map under --test-command; " \
                              "check your command exercises person.rb")
  end

  it "stays quiet when at least one mutant was killed" do
    expect(terminal_output(report_with(%i[survived killed]))).not_to include("no coverage map")
  end

  it "stays quiet when a mutant errored" do
    expect(terminal_output(report_with(%i[survived error]))).not_to include("no coverage map")
  end

  it "stays quiet when a survivor pairs with a timed-out mutant (a timeout is a kill)" do
    expect(terminal_output(report_with(%i[survived timeout]))).not_to include("no coverage map")
  end

  it "stays quiet for a subject whose only mutant hit a resource limit (no survivor)" do
    expect(terminal_output(report_with(%i[resource_limit]))).not_to include("no coverage map")
  end

  it "names a subject whose survivor pairs with a resource-limit result" do
    output = terminal_output(report_with(%i[survived resource_limit]))
    expect(output).to include("Person#adult?: no coverage map under --test-command")
  end

  it "stays quiet when every mutant was killed" do
    expect(terminal_output(report_with(%i[killed timeout]))).not_to include("no coverage map")
  end

  it "stays quiet on in-process runs, which have a coverage map" do
    expect(terminal_output(report_with(%i[survived survived], test_command: nil)))
      .not_to include("no coverage map")
  end
end
