# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# D4 (#1155): the stability policy must cover the three surfaces that moved
# in minor releases without a stated rule: exit codes, default test
# selection and the default operator set.
RSpec.describe "stability policy coverage (docs/stability.md)" do
  text = File.read(File.expand_path("../../docs/stability.md", __dir__), encoding: "UTF-8")

  it "covers exit codes" do
    expect(text).to include("### The process exit codes")
  end

  it "covers default test selection" do
    expect(text).to include("### Default test selection")
  end

  it "covers the default operator set" do
    expect(text).to include("### The default operator set")
  end
end
