# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "yaml"

RSpec.describe "bench/corpus/corpus.yml" do
  let(:corpus) { YAML.safe_load_file(File.expand_path("../../bench/corpus/corpus.yml", __dir__)) }

  it "pins every fix by its full commit SHA on a public https repository" do
    corpus.each do |name, entry|
      expect(entry.fetch("fix")).to match(/\A\h{40}\z/), name
      expect(entry.fetch("repo")).to match(%r{\Ahttps://github\.com/[\w.-]+/[\w.-]+\.git\z}), name
    end
  end

  it "records one known verdict per entry and no fix twice" do
    expect(corpus.values.map { |entry| entry.fetch("expected") }.uniq)
      .to all(satisfy { |verdict| %w[catch_exact catch_near miss no_mutants].include?(verdict) })
    expect(corpus.values.map { |entry| entry.fetch("fix") }.uniq.size).to eq(corpus.size)
  end
end
