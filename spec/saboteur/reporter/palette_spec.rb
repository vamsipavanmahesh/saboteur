# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::Palette do
  let(:terminal) { StringIO.new.tap { |io| allow(io).to receive(:tty?).and_return(true) } }
  let(:pipe) { StringIO.new }

  def palette_for(out, **arguments)
    described_class.for(out, **arguments)
  end

  it "paints a token with its ANSI codes, and returns the text unchanged when colour is off" do
    expect(palette_for(terminal, mode: :always, environment: {}).paint(:fail, "x")).to eq("\e[31;1mx\e[0m")
    expect(palette_for(terminal, mode: :always, environment: {}).paint(:pass, "x")).to eq("\e[32mx\e[0m")
    expect(palette_for(terminal, mode: :never, environment: {}).paint(:fail, "x")).to eq("x")
  end

  it "keeps legacy colour names painting until every call site converts" do
    palette = palette_for(pipe, mode: :always, environment: {})
    expect(palette.paint(:red, "x")).to eq("\e[31mx\e[0m")
    expect(palette.paint(:magenta, "x")).to eq("\e[35mx\e[0m")
  end

  it "exposes exactly the six contract tokens" do
    expect(described_class::TOKENS.keys).to eq(%i[fail pass warn info dim head])
  end

  it "colours a terminal in auto mode" do
    expect(palette_for(terminal, environment: {}).paint(:pass, "x")).to eq("\e[32mx\e[0m")
  end

  it "stays plain for an output without tty? in auto mode" do
    expect(palette_for(Object.new, environment: {}).enabled?).to be(false)
  end

  it "lets the flag beat every environment signal, in both directions" do
    expect(palette_for(pipe, mode: :always, environment: { "NO_COLOR" => "1", "TERM" => "dumb" }).enabled?)
      .to be(true)
    expect(palette_for(terminal, mode: :never, environment: { "FORCE_COLOR" => "1" }).enabled?).to be(false)
  end

  it "lets a non-empty NO_COLOR beat FORCE_COLOR, and treats an empty NO_COLOR as unset" do
    expect(palette_for(terminal, environment: { "NO_COLOR" => "1", "FORCE_COLOR" => "1" }).enabled?).to be(false)
    expect(palette_for(terminal, environment: { "NO_COLOR" => "" }).enabled?).to be(true)
  end

  it "lets FORCE_COLOR or CLICOLOR_FORCE colour a plain pipe" do
    expect(palette_for(pipe, environment: { "FORCE_COLOR" => "1" }).enabled?).to be(true)
    expect(palette_for(pipe, environment: { "CLICOLOR_FORCE" => "1" }).enabled?).to be(true)
    expect(palette_for(pipe, environment: { "FORCE_COLOR" => "" }).enabled?).to be(false)
  end

  it "colours a known colour-capable CI in auto mode, but not a plain pipe" do
    expect(palette_for(pipe, environment: { "GITHUB_ACTIONS" => "true" }).enabled?).to be(true)
    expect(palette_for(pipe, environment: { "CI" => "true" }).enabled?).to be(false)
  end

  it "stays monochrome and ASCII under TERM=dumb even with FORCE_COLOR" do
    palette = palette_for(pipe, environment: { "TERM" => "dumb", "FORCE_COLOR" => "1" })
    expect(palette.enabled?).to be(false)
    expect(palette.glyph(:check)).to eq("v")
    expect(palette.glyph(:cross)).to eq("x")
    expect(palette.glyph(:arrow)).to eq("->")
    expect(palette.glyph(:middot)).to eq("*")
  end

  it "uses ASCII glyphs under a non-UTF-8 locale and Unicode glyphs otherwise" do
    expect(palette_for(pipe, environment: { "LANG" => "C" }).glyph(:check)).to eq("v")
    expect(palette_for(pipe, environment: { "LC_ALL" => "en_US.UTF-8", "LANG" => "C" }).glyph(:check)).to eq("✓")
    expect(palette_for(pipe, environment: {}).glyph(:arrow)).to eq("→")
  end

  it "keeps colour on a terminal when TERM names a normal terminal" do
    expect(palette_for(terminal, environment: { "TERM" => "xterm-256color" }).enabled?).to be(true)
  end

  it "keeps Unicode glyphs when TERM is a normal terminal and the locale is UTF-8" do
    palette = palette_for(pipe, environment: { "TERM" => "xterm-256color", "LANG" => "en_US.UTF-8" })
    expect(palette.glyph(:check)).to eq("\u2713")
  end

  it "prefers LC_CTYPE over LANG when LC_ALL is unset" do
    expect(palette_for(pipe, environment: { "LC_CTYPE" => "C", "LANG" => "en_US.UTF-8" }).glyph(:check)).to eq("v")
  end

  it "lists every unknown token and every valid token in the error" do
    expect { palette_for(terminal, mode: :always, environment: {}, overrides: { "error" => :red, "bogus" => :red }) }
      .to raise_error(ArgumentError, "unknown palette tokens: error, bogus (valid: fail, pass, warn, info, dim, head)")
  end

  it "lists every unknown colour and every valid colour in the error" do
    expect { palette_for(terminal, mode: :always, environment: {}, overrides: { "fail" => %i[orange purple] }) }
      .to raise_error(ArgumentError,
                      "unknown palette colours: orange, purple (valid: red, green, yellow, magenta, cyan, dim, bold)")
  end

  it "validates colours inside an array-valued override" do
    expect { palette_for(terminal, mode: :always, environment: {}, overrides: { "fail" => %i[red orange] }) }
      .to raise_error(ArgumentError, /unknown palette colours: orange/)
  end

  it "takes override colour names as strings, the shape YAML config gives them" do
    palette = palette_for(terminal, mode: :always, environment: {}, overrides: { "fail" => "magenta" })
    expect(palette.paint(:fail, "x")).to eq("\e[35mx\e[0m")
  end

  it "lets a c.palette override repaint one token end to end" do
    palette = palette_for(terminal, mode: :always, environment: {}, overrides: { "fail" => :magenta })
    expect(palette.paint(:fail, "x")).to eq("\e[35mx\e[0m")
    expect(palette.paint(:pass, "x")).to eq("\e[32mx\e[0m")
  end

  it "rejects unknown override tokens with the valid list, and unknown colour names" do
    expect { palette_for(terminal, mode: :always, environment: {}, overrides: { "error" => :red }) }
      .to raise_error(ArgumentError, /unknown palette tokens: error \(valid: fail, pass, warn, info, dim, head\)/)
    expect { palette_for(terminal, mode: :always, environment: {}, overrides: { "fail" => :orange }) }
      .to raise_error(ArgumentError, /unknown palette colours: orange/)
  end
end
