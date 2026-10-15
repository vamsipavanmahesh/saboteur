# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "agent mode when the baseline child dies", :e2e do
  let(:dir) { copy_fixture("people") }

  it "emits exactly one parseable JSON failure doc, exit 3, and the labeled warning (#289)" do
    File.write(File.join(dir, "spec", "suicide_spec.rb"), <<~RUBY)
      RSpec.describe "suicide" do
        it("ends the baseline child without a word") { exit!(1) }
      end
    RUBY

    run = saboteur(dir, "--all", "--agent")
    expect(run.status).to eq(3), run.err
    payload = JSON.parse(run.out) # raises unless stdout is exactly one JSON doc
    expect(payload).to include("status" => "error", "verdict" => "tool_failure", "exitCode" => 3)
    expect(run.err).to include("baseline check 1 failed at seed 1")
    expect(payload.fetch("message")).to include("baseline check 1 failed at seed 1")
  end
end
