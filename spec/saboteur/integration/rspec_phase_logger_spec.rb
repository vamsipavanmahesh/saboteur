# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Integration::RSpec::PhaseLogger do
  let(:out) { StringIO.new }
  let(:logger) { described_class.new(out, total: 3) }

  def example_finished(times)
    times.times { logger.example_finished(instance_double(RSpec::Core::Notifications::ExampleNotification)) }
  end

  it "prints progress every 25 examples and at the end" do
    logger = described_class.new(out, total: 51)
    51.times { logger.example_finished(instance_double(RSpec::Core::Notifications::ExampleNotification)) }
    expect(out.string.lines.map(&:strip)).to eq(["25/51 examples finished", "50/51 examples finished",
                                                 "51/51 examples finished"])
  end

  it "prints nothing until the first progress mark" do
    example_finished(2)
    expect(out.string).to eq("")
  end

  # A failure in a suite hook or a load error is not an example failure, so
  # it never reaches dump_failures; RSpec sends it as a message instead.
  it "prints non-example failure messages" do
    notification = instance_double(RSpec::Core::Notifications::MessageNotification,
                                   message: "An error occurred in a before(:suite) hook.\nFailure: boom")
    logger.message(notification)
    expect(out.string).to include("before(:suite) hook", "boom")
  end

  it "prints RSpec's formatted failures and the totals line" do
    failures = instance_double(RSpec::Core::Notifications::ExamplesNotification,
                               fully_formatted_failed_examples: "1) it fails\n   expected: true\n")
    summary = instance_double(RSpec::Core::Notifications::SummaryNotification,
                              totals_line: "3 examples, 1 failure")
    logger.dump_failures(failures)
    logger.dump_summary(summary)
    expect(out.string).to include("1) it fails", "3 examples, 1 failure")
  end
end
