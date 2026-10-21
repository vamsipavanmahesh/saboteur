# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# --quiet's whole-output contract (#1149): exactly the PR6 lines on stdout -
# one per finding, the canonical summary, the verdict - and nothing else
# anywhere: no startup lines, no progress bar, no reports line. The default
# run keeps all of them.
RSpec.describe "run --quiet", :e2e do
  it "prints exactly the findings, the summary and the verdict, with stderr silent" do
    dir = copy_fixture("people")
    run = saboteur(dir, "--quiet")
    expect(run.status).to eq(1)
    lines = run.out.lines.map(&:chomp)
    expect(lines.size).to eq(5), run.out
    expect(lines[0]).to eq("lib/people.rb:14 People::Person#adult? [missing_test] - 6efe213a68e7ddc9 (+1 more)")
    expect(lines[1]).to eq("lib/people.rb:17 People::Person#adult_by_constant? [missing_test] - 380c9ebc68496aeb")
    expect(lines[2]).to eq("lib/stage.rb:8 Stage.for [missing_test] - 505fb39793c4a9f3 (+4 more)")
    expect(lines[3]).to match(/\Asaboteur: 33 killed, 8 survived in \d+s - score 80\.5%\z/)
    expect(lines[4]).to match(/exit 1 - 8 survivors/)
    expect(run.out).not_to include("Reports:")
    expect(run.err).to eq("")
  end

  it "still prints the gate note on stderr when a gate fails, with startup and progress silent" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "spec", "empty_spec.rb"),
               "RSpec.describe('nothing') { it('passes') { expect(1).to eq(1) } }\n")
    run = saboteur(dir, "--quiet", "--threshold", "50", "--test", "spec/empty_spec.rb")
    expect(run.status).to eq(1)
    expect(run.err).to eq("saboteur: no mutant was tested, so there is no score to compare with --threshold\n")
    expect(run.out).to include("lib/stage.rb:7 Stage.for [untested]")
    expect(run.out).to match(%r{saboteur: 7 subjects untested in \d+s - score n/a \(threshold 50\)})
    expect(run.out).to match(/exit 1 - gate limits exceeded/)
    expect(run.out).not_to include("Reports:")
  end

  it "keeps the startup lines, the progress bar and the reports line without --quiet" do
    dir = copy_fixture("people")
    run = saboteur(dir)
    expect(run.status).to eq(1)
    expect(run.err).to include(".:killed S:survived")
    expect(run.out).to include("Reports:")
  end
end
