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

  it "paints ASCII glyphs when the palette falls back" do
    ascii = described_class.new(config, out: out, palette: Saboteur::Reporter::Palette.new(enabled: false, ascii: true))
    ascii.send(:render_summary, golden_checks)
    expect(out.string).to include("v Ruby", "x SimpleCov", "exit 1 - fix the x above")
  end

  describe "runtime check" do
    before { allow(Saboteur::EnvironmentHints).to receive(:all).and_return([]) }

    it "passes with the Ruby and RSpec versions and the bundler note" do
      allow(doctor).to receive(:rspec_version).and_return("3.13.1")
      result = doctor.send(:runtime_check)
      expect(result.status).to eq(:pass)
      expect(result.detail).to eq("Ruby #{RUBY_VERSION} · RSpec 3.13.1 · bundler ok")
    end

    it "fails with the install fix when RSpec cannot load" do
      allow(doctor).to receive(:rspec_version).and_return(nil)
      result = doctor.send(:runtime_check)
      expect(result.status).to eq(:fail)
      expect(result.fix).to eq("bundle install, or add rspec to your Gemfile")
    end

    it "drops the bundler note when environment hints exist" do
      allow(Saboteur::EnvironmentHints).to receive(:all).and_return(["hint"])
      allow(doctor).to receive(:rspec_version).and_return("3.13.1")
      expect(doctor.send(:runtime_check).detail).not_to include("bundler ok")
    end
  end

  it "warns with the environment hints and the re-run fix" do
    allow(Saboteur::EnvironmentHints).to receive(:all).and_return(["hint one", "hint two"])
    result = doctor.send(:environment_check)
    expect(result.status).to eq(:warn)
    expect(result.detail).to eq("environment: hint one; hint two")
    expect(result.fix).to eq("address the environment hints, then re-run saboteur doctor")
  end

  describe "sandbox check" do
    it "passes on Landlock ABI 3+" do
      allow(doctor).to receive(:sandbox_abi).and_return(3)
      expect(doctor.send(:sandbox_check).detail).to eq("sandbox: Landlock ABI 3")
    end

    it "warns with the kernel fix when the ABI is older" do
      allow(doctor).to receive(:sandbox_abi).and_return(2)
      result = doctor.send(:sandbox_check)
      expect(result.status).to eq(:warn)
      expect(result.detail).to eq("sandbox: Landlock ABI 2 < 3 - children run with the hazard guard only")
      expect(result.fix).to eq("kernel 6.2+ for full isolation, or accept reduced isolation")
    end

    it "fails when c.sandbox = \"strict\" refuses the degraded run" do
      strict = described_class.new(Saboteur::Config.new({ "sandbox" => "strict" }), out: out, palette: palette)
      allow(strict).to receive(:sandbox_abi).and_return(2)
      result = strict.send(:sandbox_check)
      expect(result.status).to eq(:fail)
      expect(result.detail).to eq('sandbox: Landlock ABI 2 < 3 - c.sandbox = "strict" refuses to run')
      expect(result.fix).to eq("kernel 6.2+ for full isolation, or set c.sandbox = true to run degraded")
    end

    it "warns with the Seatbelt opt-in on macOS" do
      allow(doctor).to receive(:sandbox_abi).and_return(0)
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(true)
      result = doctor.send(:sandbox_check)
      expect(result.status).to eq(:warn)
      expect(result.detail).to eq("sandbox: macOS has no Landlock - mutants run unsandboxed")
      expect(result.fix).to eq('opt in with c.sandbox = "seatbelt", or run inside a container')
    end

    it "is silent when the sandbox is off" do
      off = described_class.new(Saboteur::Config.new({ "sandbox" => false }), out: out, palette: palette)
      expect(off.send(:sandbox_check)).to be_nil
    end
  end

  it "reports the unchanged suite with its example count and cost" do
    health = instance_double(Saboteur::BaselineHealth, call: %w[a b c d e f])
    allow(Saboteur::BaselineHealth).to receive(:new).and_return(health)
    result = doctor.send(:suite_check)
    expect(result.status).to eq(:pass)
    expect(result.detail).to match(/\Aunchanged suite green \(6 examples, [\d.]+s\)\z/)
  end

  it "formats seconds without a trailing .0" do
    expect(doctor.send(:format_seconds, 0.31)).to eq("0.3s")
    expect(doctor.send(:format_seconds, 14.0)).to eq("14s")
  end

  describe "SimpleCov guard check (#312)" do
    def with_helper(contents, name = "spec_helper.rb")
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        File.write(File.join(dir, "spec", name), contents)
        allow(config).to receive(:root).and_return(dir)
        yield
      end
    end

    it "is silent when no spec helper starts SimpleCov" do
      Dir.mktmpdir do |dir|
        allow(config).to receive(:root).and_return(dir)
        expect(doctor.send(:simplecov_guard_check)).to be_nil
      end
    end

    it "fails with the wrap fix naming the file and line of SimpleCov.start" do
      with_helper("require \"simplecov\"\n\nSimpleCov.start do\nend\n") do
        result = doctor.send(:simplecov_guard_check)
        expect(result.status).to eq(:fail)
        expect(result.detail).to eq("SimpleCov is not guarded - it steals coverage from saboteur")
        expect(result.fix).to eq('wrap it: if ENV["COVERAGE"]  (spec/spec_helper.rb:3)')
      end
    end

    it "passes when the start is guarded by ENV[\"COVERAGE\"]" do
      with_helper("if ENV[\"COVERAGE\"]\n  SimpleCov.start\nend\n") do
        result = doctor.send(:simplecov_guard_check)
        expect(result.status).to eq(:pass)
        expect(result.detail).to eq('SimpleCov: guarded by ENV["COVERAGE"]')
      end
    end

    it "checks rails_helper.rb too" do
      with_helper("SimpleCov.start\n", "rails_helper.rb") do
        result = doctor.send(:simplecov_guard_check)
        expect(result.fix).to eq('wrap it: if ENV["COVERAGE"]  (spec/rails_helper.rb:1)')
      end
    end
  end

  describe "ignore file health" do
    def with_project(lib_source, ignore_source)
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "lib", "person.rb"), lib_source)
        File.write(File.join(dir, "config", "saboteur_ignore.rb"), ignore_source) if ignore_source
        allow(config).to receive(:root).and_return(dir)
        yield
      end
    end

    let(:person) { "class Person\n  def adult?\n    true\n  end\nend\n" }

    it "is silent without ignore entries" do
      with_project(person, nil) { expect(doctor.send(:ignore_health_check)).to be_nil }
    end

    it "passes when every entry names a live subject" do
      ignore = <<~RUBY
        Saboteur.ignore do |i|
          i.mutation "a", subject: "Person#adult?", reason: "equivalent"
        end
      RUBY
      with_project(person, ignore) do
        result = doctor.send(:ignore_health_check)
        expect(result.status).to eq(:pass)
        expect(result.detail).to eq("ignore file: 1 entry, all live")
      end
    end

    it "warns with the stale count and the refresh fix" do
      ignore = <<~RUBY
        Saboteur.ignore do |i|
          i.mutation "a", subject: "Person#adult?", reason: "equivalent"
          i.mutation "b", subject: "Person#gone?", reason: "removed"
          i.mutation "c", subject: "Ghost#gone?", reason: "removed"
        end
      RUBY
      with_project(person, ignore) do
        result = doctor.send(:ignore_health_check)
        expect(result.status).to eq(:warn)
        expect(result.detail).to eq("ignore file: 3 entries, 2 stale")
        expect(result.fix).to eq("remove or refresh the stale entries in config/saboteur_ignore.rb")
      end
    end

    it "warns when an included file does not parse" do
      ignore = <<~RUBY
        Saboteur.ignore do |i|
          i.mutation "a", subject: "Person#adult?", reason: "equivalent"
        end
      RUBY
      with_project("def broken(\n", ignore) do
        result = doctor.send(:ignore_health_check)
        expect(result.status).to eq(:warn)
        expect(result.detail).to eq("ignore file: health check incomplete - an included file does not parse")
        expect(result.fix).to eq("fix the parse error, then re-run saboteur doctor")
      end
    end
  end

  it "renders the checks in golden order: runtime, suite, then the rest" do
    doctor = described_class.new(config, out: out, suite: true, palette: palette)
    allow(doctor).to receive(:runtime_check).and_return(golden_checks[0])
    allow(doctor).to receive(:environment_check).and_return(nil)
    allow(doctor).to receive(:simplecov_guard_check).and_return(golden_checks[2])
    allow(doctor).to receive(:boot_silently)
    allow(doctor).to receive(:suite_check).and_return(golden_checks[1])
    allow(doctor).to receive(:sandbox_check).and_return(golden_checks[3])
    allow(doctor).to receive(:ignore_health_check).and_return(golden_checks[4])
    expect(doctor.call).to be(false)
    expect(out.string).to eq(golden_text)
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
