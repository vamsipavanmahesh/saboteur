# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Integration::RSpec, "load-quit check (#378)" do
  def quit?(world)
    described_class.new(Saboteur::Config.new({}, root: Dir.pwd)).send(:quit_while_loading?, world)
  end

  # rspec-core 3.10 and older have wants_to_quit only; asking for
  # rspec_is_quitting there crashes setup with NoMethodError.
  it "reads wants_to_quit on an rspec-core without rspec_is_quitting (the 3.10 shape)" do
    world = Struct.new(:wants_to_quit).new(true)
    expect(quit?(world)).to be(true)
  end

  it "does not quit when the 3.10-shape world does not want to" do
    world = Struct.new(:wants_to_quit).new(false)
    expect(quit?(world)).to be(false)
  end

  it "also honors rspec_is_quitting where it exists (rspec-core 3.11+)" do
    world = Struct.new(:wants_to_quit, :rspec_is_quitting).new(false, true)
    expect(quit?(world)).to be(true)
  end

  it "does not quit when neither flag is set" do
    world = Struct.new(:wants_to_quit, :rspec_is_quitting).new(false, false)
    expect(quit?(world)).to be(false)
  end
end
