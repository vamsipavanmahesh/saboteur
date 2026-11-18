# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "bundler"

RSpec.describe "development dependency compatibility" do
  # regexp_parser 2.13.2 made the syntax API used by json_schemer private.
  # Keep that broken resolution out without freezing working 2.x releases.
  it "excludes 2.13.2 without excluding neighboring parser releases" do
    dependency = Bundler.definition.dependencies.find { |entry| entry.name == "regexp_parser" }
    expect(dependency).not_to be_nil

    requirement = dependency.requirement
    expect(requirement.satisfied_by?(Gem::Version.new("2.13.2"))).to be(false)
    %w[2.13.1 2.13.3 2.13.4].each do |version|
      expect(requirement.satisfied_by?(Gem::Version.new(version))).to be(true)
    end
  end
end
