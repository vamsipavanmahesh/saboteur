# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::Checks::Whitespace, :fixture do
  let(:base) { @base }

  def check
    repository = @fixture.repository(base: base)
    described_class.new(repository: repository, command_runner: @fixture.runner, head: @fixture.head).call
  end

  it "passes a clean change (valid control)" do
    @fixture.write("a.txt", "clean\n")
    @fixture.commit("clean")
    expect(check.status).to eq(:passed)
  end

  it "fails trailing whitespace" do
    @fixture.write("a.txt", "dirty \n")
    @fixture.commit("dirty")
    expect(check.status).to eq(:failed)
  end

  it "fails a conflict marker" do
    @fixture.write("a.txt", "<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> other\n")
    @fixture.commit("marker")
    expect(check.status).to eq(:failed)
  end
end
