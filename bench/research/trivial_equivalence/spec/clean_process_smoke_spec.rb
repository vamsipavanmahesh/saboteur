# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# Runs the documented entry points in a fresh Ruby process, so a missing
# require cannot be hidden by what the spec process already loaded.
# rubocop:disable-next Metrics/BlockLength
RSpec.describe "clean process entry points" do
  let(:research_root) { File.expand_path("..", __dir__) }

  def run_ruby(*arguments)
    Open3.capture3(RbConfig.ruby, *arguments, chdir: research_root)
  end

  it "loads the library and judges a reflective file at the relaxed level" do
    script = <<~RUBY
      require "./lib/trivial_equivalence"
      judge = TrivialEquivalence::EquivalenceJudge.new(level: :relaxed)
      verdict = judge.judge(original_source: "def a\\n  caller\\nend\\n", mutated_source: "def a\\n\\n  caller\\nend\\n", path: "a.rb")
      puts verdict.reason
    RUBY
    output, error, status = run_ruby("-e", script)
    expect([status.success?, output.strip, error]).to eq([true, "reflection", ""])
  end

  it "runs measure.rb on a small project" do
    Dir.mktmpdir do |project|
      File.write(File.join(project, "sample.rb"), <<~RUBY)
        class Sample
          def total(value)
            value + 1
          end
        end
      RUBY
      report = File.join(project, "report.json")
      _output, error, status = run_ruby("measure.rb", "--project", project, "--files", "*.rb", "--out", report)
      result = JSON.parse(File.read(report))
      expect([status.success?, error, result["mutants"].positive?]).to eq([true, "", true])
      expected_command = ["ruby", "measure.rb", "--project", project, "--files", "*.rb", "--out", report]
      expect(result.dig("provenance", "command")).to eq(expected_command)
    end
  end
end
