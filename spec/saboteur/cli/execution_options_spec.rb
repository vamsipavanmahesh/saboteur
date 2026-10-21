# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"

RSpec.describe Saboteur::CLI::ExecutionOptions do
  it "describes --test-command with its trade-offs" do
    cli = Saboteur::CLI.new([], out: StringIO.new, err: StringIO.new)
    parser = OptionParser.new
    cli.send(:define_execution_options, parser)
    expect(parser.to_s).to include(
      "Run CMD per mutant in the project root; exit 0 means the mutant survived. " \
      "For apps that cannot load in this Ruby; much slower, serial, no coverage"
    )
  end
end
