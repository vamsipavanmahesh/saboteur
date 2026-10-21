# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe "base_snapshot and docs_update", :fixture do
  def repo
    @fixture.repository(base: @base)
  end

  it "passes when --base equals local origin/main (valid control)" do
    @fixture.git("update-ref", "refs/remotes/origin/main", @base)
    @fixture.write("a.txt", "x\n")
    @fixture.commit("change")
    result = Preflight::Checks::BaseSnapshot.new(repository: repo, base: @base).call
    expect(result.status).to eq(:passed)
  end

  it "asks for review when --base differs from local origin/main" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("change")
    @fixture.git("update-ref", "refs/remotes/origin/main", @fixture.head)
    result = Preflight::Checks::BaseSnapshot.new(repository: repo, base: @base).call
    expect([result.status, result.reason]).to match([:review_required, %r{differs from local origin/main}])
  end

  it "is not applicable, and says so, when there is no origin/main" do
    result = Preflight::Checks::BaseSnapshot.new(repository: repo, base: @base).call
    expect([result.status, result.reason]).to match([:not_applicable, /unverified/])
  end

  it "asks for review when a CLI file changed without a docs/ change" do
    @fixture.write("lib/saboteur/cli.rb", "x\n")
    @fixture.commit("cli")
    result = Preflight::Checks::DocsUpdate.new(repository: repo).call
    expect([result.status, result.reason]).to match([:review_required, %r{docs/ did not}])
  end

  it "passes when a docs/ file changes with the CLI file (valid control)" do
    @fixture.write("lib/saboteur/cli.rb", "x\n")
    @fixture.write("docs/usage.md", "doc\n")
    @fixture.commit("cli and docs")
    expect(Preflight::Checks::DocsUpdate.new(repository: repo).call.status).to eq(:passed)
  end
  it "still asks for review when only README.md changes with the CLI file" do
    @fixture.write("lib/saboteur/cli.rb", "x\n")
    @fixture.write("README.md", "doc\n")
    @fixture.commit("cli and readme")
    expect(Preflight::Checks::DocsUpdate.new(repository: repo).call.status).to eq(:review_required)
  end

  it "is not applicable when no CLI file changed" do
    @fixture.write("lib/other.rb", "x\n")
    @fixture.commit("other")
    expect(Preflight::Checks::DocsUpdate.new(repository: repo).call.status).to eq(:not_applicable)
  end
end
