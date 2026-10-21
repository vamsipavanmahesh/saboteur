# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# --quiet's engine side (#1149): silent diagnostics print nothing - no
# inform chatter, none of the quiet-start lines, no progress legend or
# marks - while warnings still land in report.warnings for the JSON, HTML
# and agent consumers that never see stderr.
RSpec.describe Saboteur::Engine::Diagnostics, "silent (#1149)" do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err, silent: true) }

  it "prints nothing for inform, announce or announce_demoted, but keeps the warning records" do
    diagnostics.inform("building coverage map")
    diagnostics.announce("selected by constant reference")
    diagnostics.announce_demoted("not running changed specs")
    expect(err.string).to eq("")
    expect(diagnostics.warnings).to eq(["selected by constant reference", "not running changed specs"])
  end

  it "prints none of the quiet-start lines" do
    diagnostics.quiet_start_header(scope: "whole project", seed: 1, operators: 37)
    diagnostics.quiet_baseline(passes: 2, elapsed: 0.1, tests: 6, cached: false)
    diagnostics.quiet_inference(2)
    expect(err.string).to eq("")
  end

  it "prints no progress legend, marks or tail chunk" do
    diagnostics.start_progress(3)
    3.times { diagnostics.progress(instance_double(Saboteur::MutantResult, status: :killed)) }
    diagnostics.finish_progress
    expect(err.string).to eq("")
  end

  it "still informs when not silent" do
    loud = described_class.new(err)
    loud.inform("building coverage map")
    expect(err.string).to eq("saboteur: building coverage map\n")
  end
end
