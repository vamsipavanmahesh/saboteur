# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Ruby 4.0 moved fiddle out of the default gems, but saboteur loads fiddle
# lazily through FiddleLoader's refusing door (#639), so it is no runtime
# dependency: a bundle without fiddle installs and boots, and only a
# sandbox-layer probe names the fixes when fiddle is missing.
RSpec.describe "saboteur.gemspec" do
  let(:gemspec) { Gem::Specification.load(File.expand_path("../../saboteur.gemspec", __dir__)) }

  it "declares every library it requires that is not part of Ruby's core" do
    runtime = gemspec.runtime_dependencies.map(&:name)
    expect(runtime).to include("prism")
    expect(runtime).not_to include("fiddle")
  end
end
