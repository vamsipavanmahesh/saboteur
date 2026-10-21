# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# README: "kills split by cause (`kills: 7 by a failed assertion, 1 by a
# crash`)". The split is --verbose debug detail; the people fixture kills
# both ways.
require "support/e2e_helpers"

RSpec.describe "kills split by cause", :e2e do
  include E2EHelpers

  it "prints the assertion/crash split under --verbose" do
    run = saboteur(copy_fixture("people"), "--verbose")

    expect(run.out).to include("kills: 23 by a failed assertion, 10 by a crash")
    expect(run.out).to include("crash kills by operator: body_nil 2 of 5, body_raise 7 of 7")
  end
end
