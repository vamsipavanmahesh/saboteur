# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Ruby 4.0 moved fiddle out of the default gems, so a gem that requires it
# must say so, or it fails to load in a bundle that lacks fiddle.
RSpec.describe "saboteur.gemspec" do
  let(:gemspec) { Gem::Specification.load(File.expand_path("../../saboteur.gemspec", __dir__)) }

  it "declares every library it requires that is not part of Ruby's core" do
    runtime = gemspec.runtime_dependencies.map(&:name)
    expect(runtime).to include("prism", "fiddle")
  end
end
