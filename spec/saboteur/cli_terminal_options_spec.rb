# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require_relative "../support/report_helpers"

RSpec.describe Saboteur::CLI, "terminal options" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:reporter) { instance_double(Saboteur::Reporter::Terminal, call: nil) }

  before do
    engine = instance_double(Saboteur::Engine, call: report_of(result_for(:killed)))
    allow(Saboteur::Engine).to receive(:new).and_return(engine)
    allow(Saboteur::Reporter::Terminal).to receive(:new).and_return(reporter)
  end

  def run_with(*flags)
    described_class.new(["run", *flags], out: out, err: err).call
  end

  it "defaults to a quiet reporter with automatic colour" do
    run_with
    expect(Saboteur::Reporter::Terminal).to have_received(:new).with(out, verbose: false, color: :auto)
  end

  it "passes --verbose to the reporter" do
    run_with("--verbose")
    expect(Saboteur::Reporter::Terminal).to have_received(:new).with(out, verbose: true, color: :auto)
  end

  it "passes --color and --no-color to the reporter" do
    run_with("--color")
    expect(Saboteur::Reporter::Terminal).to have_received(:new).with(out, verbose: false, color: :always)
    run_with("--no-color")
    expect(Saboteur::Reporter::Terminal).to have_received(:new).with(out, verbose: false, color: :never)
  end
end
