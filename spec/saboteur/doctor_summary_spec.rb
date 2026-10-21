# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "saboteur/doctor"

RSpec.describe Saboteur::Doctor, "summary (#333)" do
  let(:out) { StringIO.new }
  let(:config) { Saboteur::Config.new }
  let(:palette) { Saboteur::Reporter::Palette.new(enabled: false) }
  let(:doctor) { described_class.new(config, out: out, palette: palette) }

  before { allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!) }

  def check(status, detail, fix = nil)
    described_class::Check.new(status:, detail:, fix:)
  end

  # The pinned golden: one line per check, every failure and warning
  # followed by its exact fix, the exit line last when anything failed.
  let(:golden_checks) do
    [check(:pass, "Ruby 3.3.7 · RSpec 3.13 · bundler ok"),
     check(:pass, "unchanged suite green (6 examples, 0.3s)"),
     check(:fail, "SimpleCov is not guarded - it steals coverage from saboteur",
           'wrap it: if ENV["COVERAGE"]  (spec/spec_helper.rb:4)'),
     check(:warn, "sandbox: Landlock ABI 2 < 3 - children run with the hazard guard only",
           "kernel 6.2+ for full isolation, or accept reduced isolation"),
     check(:pass, "ignore file: 6 entries, all live")]
  end

  let(:golden_text) do
    <<~TEXT
      Doctor summary (details: saboteur doctor -v):
      ✓ Ruby 3.3.7 · RSpec 3.13 · bundler ok
      ✓ unchanged suite green (6 examples, 0.3s)
      ✗ SimpleCov is not guarded - it steals coverage from saboteur
          Fix: wrap it: if ENV["COVERAGE"]  (spec/spec_helper.rb:4)
      ! sandbox: Landlock ABI 2 < 3 - children run with the hazard guard only
          Fix: kernel 6.2+ for full isolation, or accept reduced isolation
      ✓ ignore file: 6 entries, all live
      exit 1 - fix the ✗ above before trusting a run
    TEXT
  end

  it "pins the golden summary in monochrome" do
    doctor.send(:render_summary, golden_checks)
    expect(out.string).to eq(golden_text)
  end

  it "pins the golden summary in colour: glyphs and the exit line painted, fixes plain" do
    coloured = described_class.new(config, out: out, palette: Saboteur::Reporter::Palette.new(enabled: true))
    coloured.send(:render_summary, golden_checks)
    pass, suite, fail_c, warn_c, ignore = golden_checks
    expect(out.string).to eq(
      "Doctor summary (details: saboteur doctor -v):\n" \
      "\e[32m✓ #{pass.detail}\e[0m\n" \
      "\e[32m✓ #{suite.detail}\e[0m\n" \
      "\e[31;1m✗ #{fail_c.detail}\e[0m\n    Fix: #{fail_c.fix}\n" \
      "\e[33m! #{warn_c.detail}\e[0m\n    Fix: #{warn_c.fix}\n" \
      "\e[32m✓ #{ignore.detail}\e[0m\n" \
      "\e[31;1mexit 1 - fix the ✗ above before trusting a run\e[0m\n"
    )
  end

  it "prints no exit line when only warnings are present" do
    doctor.send(:render_summary, [golden_checks[0], golden_checks[3]])
    expect(out.string).not_to include("exit 1")
  end

  describe "summary verdict" do
    before do
      allow(doctor).to receive(:environment_check).and_return(nil)
      allow(doctor).to receive(:boot_silently)
      allow(doctor).to receive(:sandbox_check).and_return(nil)
    end

    it "returns false and prints the exit line when a check fails" do
      allow(doctor).to receive(:runtime_check).and_return(check(:fail, "RSpec not found", "bundle install"))
      expect(doctor.call).to be(false)
      expect(out.string).to include("Doctor summary (details: saboteur doctor -v):", "    Fix: bundle install",
                                    "exit 1 - fix the ✗ above before trusting a run")
    end

    it "returns true and prints no exit line when only warnings are present" do
      allow(doctor).to receive(:runtime_check).and_return(check(:pass, "Ruby fine"))
      allow(doctor).to receive(:sandbox_check).and_return(check(:warn, "sandbox: degraded", "accept it"))
      expect(doctor.call).to be(true)
      expect(out.string).not_to include("exit 1")
    end
  end
end
