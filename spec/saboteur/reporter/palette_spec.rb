# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::Palette do
  let(:terminal) { StringIO.new.tap { |io| allow(io).to receive(:tty?).and_return(true) } }

  it "colours a terminal in auto mode" do
    expect(described_class.for(terminal, environment: {}).paint(:red, "x")).to eq("\e[31mx\e[0m")
  end

  it "stays plain when NO_COLOR is set, unless colour is forced" do
    expect(described_class.for(terminal, environment: { "NO_COLOR" => "1" }).paint(:red, "x")).to eq("x")
    expect(described_class.for(terminal, mode: :always, environment: { "NO_COLOR" => "1" }).paint(:red, "x"))
      .to include("\e[31m")
  end

  it "stays plain when the output is not a terminal, or colour is off" do
    expect(described_class.for(StringIO.new, environment: {}).paint(:red, "x")).to eq("x")
    expect(described_class.for(terminal, mode: :never, environment: {}).paint(:red, "x")).to eq("x")
  end
end

RSpec.describe Saboteur::Reporter::Palette, "auto mode on odd outputs" do
  it "stays plain for an output without tty? and for a terminal with an empty NO_COLOR" do
    expect(described_class.for(Object.new, environment: {}).enabled?).to be(false)
    tty = StringIO.new.tap { |io| allow(io).to receive(:tty?).and_return(true) }
    expect(described_class.for(tty, environment: { "NO_COLOR" => "" }).enabled?).to be(true)
    expect(described_class.for(tty, environment: { "NO_COLOR" => "1" }).enabled?).to be(false)
    expect(described_class.for(StringIO.new, environment: { "NO_COLOR" => "" }).enabled?).to be(false)
  end
end
