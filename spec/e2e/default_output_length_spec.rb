# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

# D1 end to end: a whole-project run prints the one-line findings list,
# expands only the top three blocks and closes with the "more findings"
# line; --details or a --since run keeps a block for every finding.
RSpec.describe "default output length (end to end)", :e2e do
  before(:context) do
    @run = saboteur(copy_fixture("d1_output"))
  end

  # One finding per surviving statement: the surviving mutants group by the
  # line they sit on.
  def finding_count(run)
    mutants(run).select { |mutant| mutant["status"] == "Survived" }
                .map { |mutant| mutant.dig("location", "start", "line") }.uniq.size
  end

  it "lists every finding but expands only the top three, then closes with the real count" do
    findings = finding_count(@run)
    expect(findings).to be > 3
    expect(@run.out.scan(%r{^lib/widget\.rb:\d+ Widget#\w+ }).size).to eq(findings)
    expect(@run.out.scan(%r{^\d+\. lib/widget\.rb:\d+ }).size).to eq(3)
    expect(@run.out).to include("... #{findings - 3} more findings - saboteur survivors " \
                                ".saboteur/report.json,\nor re-run with --details")
  end

  it "expands every finding under --details, with no list and no closer" do
    run = saboteur(copy_fixture("d1_output"), "--details")
    findings = finding_count(run)
    expect(run.out.scan(%r{^\d+\. lib/widget\.rb:\d+ }).size).to eq(findings)
    expect(run.out).not_to include("more findings - saboteur survivors")
  end

  it "keeps a --since run fully expanded, even past three findings" do
    dir = copy_fixture("d1_output")
    git = lambda do |*args|
      _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com",
                                         *args, chdir: dir)
      raise err unless status.success?
    end
    git.call("init", "-q")
    git.call("add", ".")
    git.call("commit", "-q", "-m", "base")
    # Touch every method, so the diff scope holds more than three findings.
    widget = File.join(dir, "lib/widget.rb")
    File.write(widget, File.read(widget).gsub("+", "-"))

    run = saboteur(dir, "--since", "HEAD")
    findings = finding_count(run)
    expect(findings).to be > 3
    expect(run.out.scan(%r{^\d+\. lib/widget\.rb:\d+ }).size).to eq(findings)
    expect(run.out).not_to include("more findings - saboteur survivors")
  end
end
