# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::SelectionOptions, "run help" do
  let(:help) do
    out = StringIO.new
    Saboteur::CLI.new(%w[run --help], out:, err: StringIO.new).call
    out.string
  end

  {
    "--operators NAMES" => "Choose operator names (default: all)",
    "--list-operators" => "List operator names and descriptions",
    "--dry-run" => "Preview mutants without boot, tests, forks or report writes",
    "--id DIGEST" => "Replay exactly one current mutant by its full digest",
    "--shard K/N" => "Run one of N deterministic candidate shards (for example 1/4)",
    "--since REF" => "Only mutate subjects changed since git REF",
    "--subject EXPR" => "Klass#meth, Klass.meth or a namespace; repeatable"
  }.each do |switch, description|
    it "describes #{switch.split.first}" do
      line = help.lines.find { |text| text.include?(switch) }
      expect(line.strip).to match(/\A#{Regexp.escape(switch)}\s+#{Regexp.escape(description)}\z/)
    end
  end
end
