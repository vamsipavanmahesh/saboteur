# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "internal baseline evidence", :e2e do
  it "captures a fresh real run with exact planned and terminal candidate identities" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "lib", "evidence_probe.rb"), "class EvidenceProbe; def value; 1; end; end")
    File.write(File.join(dir, "spec", "evidence_probe_spec.rb"), <<~RUBY)
      require_relative "../lib/evidence_probe"
      RSpec.describe EvidenceProbe do
        it("checks value") { expect(EvidenceProbe.new.value).to eq(1) }
      end
    RUBY
    script = <<~RUBY
      require "coverage"
      Coverage.setup(lines: true)
      require "saboteur"
      require "json"
      config = Saboteur::Config.load(overrides: { "max_mutants_per_method" => 1000, "include" => ["lib/evidence_probe.rb"],
                                                "rspec_args" => ["spec/evidence_probe_spec.rb"] })
      report = Saboteur::Engine.new(config, capture_evidence: true).call
      File.write("evidence.json", JSON.generate(report.run_evidence))
    RUBY
    out, err, status = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                                      RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), "-e", script, chdir: dir)

    expect(status.exitstatus).to eq(0), out + err
    evidence = JSON.parse(File.read(File.join(dir, "evidence.json")))
    expect(evidence.fetch("complete")).to be(true), evidence.fetch("issues").inspect
    expect(evidence.fetch("planned")).not_to be_empty
    expect(evidence.fetch("planned").map { |entry| entry.fetch("id") }.sort)
      .to eq(evidence.fetch("candidates").map { |entry| entry.fetch("id") }.sort)
    expect(evidence.fetch("candidates").map { |entry| entry.fetch("status") }.uniq - %w[killed survived timeout])
      .to be_empty
  end
  it "blocks malformed discovery input even alongside valid covered work" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "lib", "evidence_probe.rb"), "class EvidenceProbe; def value; 1; end; end")
    File.write(File.join(dir, "spec", "evidence_probe_spec.rb"), <<~RUBY)
      require_relative "../lib/evidence_probe"
      RSpec.describe EvidenceProbe do
        it("checks value") { expect(EvidenceProbe.new.value).to eq(1) }
      end
    RUBY
    File.write(File.join(dir, "lib", "broken.rb"), "class Broken; def ( ; end")
    script = <<~RUBY
      require "coverage"
      Coverage.setup(lines: true)
      require "saboteur"
      require "json"
      config = Saboteur::Config.load(overrides: { "max_mutants_per_method" => 1000, "include" => ["lib/evidence_probe.rb", "lib/broken.rb"],
                                                "rspec_args" => ["spec/evidence_probe_spec.rb"] })
      report = Saboteur::Engine.new(config, capture_evidence: true).call
      File.write("evidence.json", JSON.generate(report.run_evidence))
    RUBY
    out, err, status = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                                      RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), "-e", script, chdir: dir)

    expect(status.exitstatus).to eq(0), out + err
    evidence = JSON.parse(File.read(File.join(dir, "evidence.json")))
    expect(evidence.fetch("complete")).to be(false)
    expect(evidence.fetch("issues")).to include("generation:discovery:invalid_file_syntax:lib/broken.rb")
    expect(evidence.fetch("discovery_failures")).to eq([
                                                         { "file" => File.join(dir, "lib", "broken.rb"),
                                                           "reason" => "invalid_file_syntax" }
                                                       ])
    expect(evidence.fetch("planned")).not_to be_empty
    expect(evidence.fetch("planned").map { |entry| entry.fetch("id") }.sort)
      .to eq(evidence.fetch("candidates").map { |entry| entry.fetch("id") }.sort)
    expect(evidence.fetch("candidates").map { |entry| entry.fetch("status") }.uniq - %w[killed survived timeout])
      .to be_empty
  end
end
