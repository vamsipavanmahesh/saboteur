# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::Checks::ProtectedPaths, :fixture do
  let(:base) { @base }

  def check
    described_class.new(repository: @fixture.repository(base: base)).call
  end

  it "passes an ordinary change (valid control)" do
    @fixture.write("lib/ordinary.rb", "x\n")
    @fixture.commit("ordinary")
    expect(check.status).to eq(:passed)
  end

  it "passes a look-alike path that only shares a prefix with a protected directory" do
    @fixture.write(".github/workflows-extra/note.md", "x\n")
    @fixture.write("integrationx/a.rb", "x\n")
    @fixture.commit("lookalike")
    expect(check.status).to eq(:passed)
  end

  it "fails a new file under a protected directory" do
    @fixture.write(".github/workflows/new.yml", "x\n")
    @fixture.commit("child")
    expect([check.status, check.details]).to eq([:failed, ["protected: A .github/workflows/new.yml"]])
  end

  it "fails a deletion and a move out of a protected directory" do
    @fixture.write("integration/targets.yml", "x\n")
    @fixture.commit("setup")
    new_base = @fixture.head
    @fixture.git("mv", "integration/targets.yml", "elsewhere.yml")
    @fixture.commit("move out")
    result = described_class.new(repository: @fixture.repository(base: new_base)).call
    expect(result.details).to include("protected: D integration/targets.yml")
  end

  it "fails the active mutation config files that the policy does not list" do
    @fixture.write("config/saboteur_ignore.rb", "x\n")
    @fixture.commit("ignore edit")
    expect(check.details).to eq(["protected: A config/saboteur_ignore.rb"])
  end

  it "reads protection from the base policy, so a branch cannot drop its own protection" do
    @fixture.write("script/panel-gate/policy.json", JSON.generate("schema" => 1, "protectedFiles" => []))
    @fixture.write("script/check-dco", "x\n")
    @fixture.commit("weaken policy and edit")
    expect(check.details).to include("protected: A script/check-dco")
  end

  it "fails a symlink or submodule change even outside protected paths" do
    File.symlink("README.md", File.join(@fixture.directory, "innocent"))
    @fixture.commit("link")
    expect(check.details.first).to start_with("symlink or submodule")
  end

  it "is incomplete when the base policy is missing or malformed" do
    @fixture.git("rm", "-q", "script/panel-gate/policy.json")
    @fixture.commit("remove policy")
    bad_base = @fixture.head
    @fixture.write("a.txt", "x\n")
    @fixture.commit("change")
    result = described_class.new(repository: @fixture.repository(base: bad_base)).call
    expect(result.status).to eq(:incomplete)
  end

  it "is incomplete when the policy has the wrong shape" do
    @fixture.write("script/panel-gate/policy.json", JSON.generate("protectedFiles" => "nope"))
    @fixture.commit("bad shape")
    shaped_base = @fixture.head
    @fixture.write("a.txt", "x\n")
    @fixture.commit("change")
    expect(described_class.new(repository: @fixture.repository(base: shaped_base)).call.status).to eq(:incomplete)
  end
end
