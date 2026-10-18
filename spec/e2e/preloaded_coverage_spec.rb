# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "a subject file loaded before Coverage.start (end to end)", :e2e do
  it "refuses the run, naming the file and the cause" do
    dir = copy_fixture("assignments")
    preload = File.join(dir, "preload.rb")
    File.write(preload, "require File.expand_path(\"lib/assignments.rb\", __dir__)\n")

    run = saboteur(dir, env: { "RUBYOPT" => "-r#{preload}" })

    expect(run.status).to eq(3)
    expect(run.err).to include("assignments.rb", "before saboteur started coverage")
  end
end
