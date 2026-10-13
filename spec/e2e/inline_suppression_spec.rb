# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "inline suppression (end to end)", :e2e do
  it "audits suppressed candidates in terminal JSON and HTML" do
    dir = copy_fixture("inline")
    run = saboteur(dir)
    expect(run.status).to eq(0), run.err
    expect(mutants(run)).to be_empty
    entries = run.json.dig("saboteur", "inlineSuppressions")
    expect(entries.size).to be >= 4
    expect(entries.map { |entry| entry["reason"] }.uniq).to eq(["validated elsewhere"])
    expect(run.out).to include("Inline suppressions:", "validated elsewhere")
    html = File.read(File.join(dir, ".saboteur", "report.html"))
    expect(html).to include("Inline suppressions", "validated elsewhere")
  end

  it "rejects a missing reason with exit 2 naming the directive line" do
    dir = copy_fixture("inline")
    path = File.join(dir, "lib", "inline_math.rb")
    File.write(path, File.read(path).sub('reason="validated elsewhere"', ""))
    run = saboteur(dir)
    expect(run.status).to eq(2)
    expect(run.err).to include("inline_math.rb:3:", "reason")
  end
end
