# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::UnscopedSuiteWarning do
  around do |example|
    Dir.mktmpdir { |root| @root = root and example.run }
  end

  let(:err) { StringIO.new }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }

  def integration(examples: 3, files: 3)
    instance_double(Saboteur::Integration::RSpec,
                    all_tests: Array.new(examples) do |i|
                      Saboteur::Integration::TestCase.new(id: "t#{i}", file: "spec/a.rb")
                    end,
                    test_files: Array.new(files) { |i| "spec/#{i}.rb" })
  end

  def warn(config, full_passes:, integration: integration())
    described_class.call(config: Saboteur::Config.new(config, root: @root), diagnostics: diagnostics,
                         integration: integration, full_passes: full_passes)
    err.string
  end

  it "names the example, file, pass and check counts and the extra coverage build (#260)" do
    text = warn({ "since" => "origin/main", "baseline_passes" => 2 }, full_passes: 3)
    expect(text).to include("running the loaded suite unscoped: 3 examples in 3 spec files; " \
                            "3 full passes (2 baseline checks + 1 coverage map build).")
  end

  it "labels a single baseline check in the singular (#260)" do
    text = warn({ "all" => true, "baseline_passes" => 1 }, full_passes: 2)
    expect(text).to include("2 full passes (1 baseline check + 1 coverage map build)")
  end

  it "notes a reused coverage map instead of the extra build (#260)" do
    text = warn({ "all" => true, "baseline_passes" => 2 }, full_passes: 2)
    expect(text).to include("2 full passes (2 baseline checks; the cached coverage map is reused)")
    expect(text).not_to include("coverage map build")
  end

  it "adds the full --test advice at the costly-suite threshold (#260)" do
    text = warn({ "all" => true }, full_passes: 3, integration: integration(examples: 1_000))
    expect(text).to include("\n  Fix: pass --test to run only the specs you name: faster, but a mutant of a changed " \
                            "method is then killed only by those specs, so specs elsewhere that call this " \
                            "code are not run. The default inferred selection runs the specs named after " \
                            "the mutated files, a guess that can miss specs elsewhere.")
  end

  it "stays quiet for a scoped run (#260)" do
    expect(warn({ "tests" => ["spec/a.rb"] }, full_passes: 3)).to eq("")
    expect(warn({}, full_passes: 3)).to eq("")
  end
end

RSpec.describe Saboteur::Engine::UnscopedSuiteWarning, "check count edge (#296)" do
  it "pluralizes zero baseline checks too" do
    expect(described_class.send(:checks_label, { "baseline_passes" => 0 })).to eq("0 baseline checks")
    expect(described_class.send(:checks_label, { "baseline_passes" => 1 })).to eq("1 baseline check")
  end
end
