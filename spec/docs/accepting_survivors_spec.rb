# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# D3 (#1154): one primary story for accepting a survivor. The handling
# section names the ignore list as the one place and frames the inline
# directive and baseline accept as advanced paths, not equal alternatives.
RSpec.describe "accepting a survivor (docs/best-practices.md)" do
  text = File.read(File.expand_path("../../docs/best-practices.md", __dir__), encoding: "UTF-8")
  section = text[/^## Handling surviving mutants\n(.*?)^## /m, 1].to_s

  it "names the ignore list as the one place a survivor is accepted" do
    expect(section).to include("The ignore list is the one place a survivor is accepted")
  end

  it "frames the inline directive and baseline accept as advanced paths" do
    expect(section).to include("saboteur:disable-line", "saboteur baseline accept", "advanced paths")
  end
end
