# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::Checks::Signoff, :fixture do
  let(:base) { @base }

  def check
    described_class.new(repository: @fixture.repository(base: base)).call
  end

  it "passes an exact sign-off from the author (valid control)" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("ok")
    expect(check.status).to eq(:passed)
  end

  it "fails a missing sign-off" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("none", signoff: nil)
    expect(check.status).to eq(:failed)
  end

  it "fails a sign-off for a different person" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("other", signoff: "Someone Else <else@example.test>")
    expect(check.status).to eq(:failed)
  end

  it "fails when the author appears only as a substring of a longer line" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("substring", signoff: "Fixture Author <author@example.test> and friends")
    expect(check.status).to eq(:failed)
  end

  it "fails AI attribution even with a valid sign-off" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("attrib\n\nCo-Authored-By: Claude <noreply@anthropic.com>")
    expect(check.details.join).to include("AI attribution")
  end

  it "allows a human Co-authored-by trailer (valid control)" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("pair\n\nCo-authored-by: Real Person <real@example.test>")
    expect(check.status).to eq(:passed)
  end

  it "does not block a human whose name or address resembles a tool (valid control)" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("humans\n\nCo-authored-by: Claude Martin <claude.martin@example.test>\n" \
                    "Co-authored-by: Devin Cursor <instinct@example.test>")
    expect(check.status).to eq(:passed)
  end

  it "fails a Co-authored-by trailer naming an AI tool, and a generated-by line" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("tool\n\nCo-authored-by: Claude <noreply@anthropic.com>")
    @fixture.write("b.txt", "x\n")
    @fixture.commit("tool2\n\nGenerated with Claude Code")
    expect(check.details.grep(/AI attribution/).length).to eq(2)
  end

  it "checks every commit, not only the last" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("first", signoff: nil)
    @fixture.write("b.txt", "x\n")
    @fixture.commit("second")
    expect(check.details.length).to eq(1)
  end
end
