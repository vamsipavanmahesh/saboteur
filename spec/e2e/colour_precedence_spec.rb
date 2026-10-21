# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The palette precedence chain, proven end to end through the real binary
# (PR1c): NO_COLOR beats FORCE_COLOR, --color=always beats NO_COLOR,
# TERM=dumb and a non-UTF-8 locale select the ASCII glyphs, and a CI pipe
# keeps colour in auto mode.
RSpec.describe "colour precedence through the CLI", :e2e do
  let(:dir) { copy_fixture("people") }

  def run_err(**env)
    saboteur(dir, env: env).err
  end

  it "lets NO_COLOR kill colour even when FORCE_COLOR is set" do
    expect(run_err("NO_COLOR" => "1", "FORCE_COLOR" => "1").bytes).not_to include(0x1b)
  end

  it "lets --color=always beat NO_COLOR" do
    expect(saboteur(dir, "--color=always", env: { "NO_COLOR" => "1" }).err).to include("\e[")
  end

  it "forces monochrome and the ASCII glyphs under TERM=dumb" do
    err = run_err("TERM" => "dumb")
    expect(err.bytes).not_to include(0x1b)
    expect(err).to include("* whole project *")
    expect(err).not_to include("·", "✓", "✗", "→")
  end

  it "selects the ASCII glyphs under a non-UTF-8 locale with no flag" do
    err = run_err("LANG" => "C", "LC_ALL" => "C")
    expect(err).to include("* whole project *")
    expect(err).not_to include("·", "✓", "✗", "→")
  end

  it "keeps colour on a pipe when GITHUB_ACTIONS is set" do
    expect(run_err("GITHUB_ACTIONS" => "1").bytes).to include(0x1b)
  end
end
