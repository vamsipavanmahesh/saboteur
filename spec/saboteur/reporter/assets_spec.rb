# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "rubygems"

RSpec.describe "vendored mutation-testing-elements asset" do
  assets = File.expand_path("../../../lib/saboteur/reporter/assets", __dir__)
  bundle = File.join(assets, "mutation_report.js")
  license = File.join(assets, "mutation_report.LICENSE")

  it "ships the bundle and its Apache-2.0 license" do
    expect(File.file?(bundle)).to be(true)
    expect(File.file?(license)).to be(true)
    expect(File.read(license, 200)).to include("Apache License", "Version 2.0")
  end

  it "pins the exact upstream version and URL in the bundle header" do
    header = File.readlines(bundle, chomp: true).first(8)
    expect(header.grep(/Pinned version: 3\.9\.0/)).not_to be_empty
    expect(header.grep(%r{registry\.npmjs\.org/mutation-testing-elements/-/mutation-testing-elements-3\.9\.0\.tgz}))
      .not_to be_empty
  end

  it "is byte-identical to the recorded upstream file below the header" do
    lines = File.readlines(bundle)
    header = lines.first(8)
    body = lines.drop(8)
    recorded = header.join[/Upstream file sha256: ([0-9a-f]{64})/, 1]
    expect(recorded).not_to be_nil
    expect(Digest::SHA256.hexdigest(body.join)).to eq(recorded)
  end

  it "is included in the gem files" do
    gemspec = Gem::Specification.load(File.expand_path("../../../saboteur.gemspec", __dir__))
    expect(gemspec.files).to include("lib/saboteur/reporter/assets/mutation_report.js",
                                     "lib/saboteur/reporter/assets/mutation_report.LICENSE")
  end
end
