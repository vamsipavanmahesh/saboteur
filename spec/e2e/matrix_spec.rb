# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "--matrix (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }
  let(:subject_name) { "People::Person#adult?" }

  before do
    File.write(File.join(dir, "spec", "twin_spec.rb"), <<~RUBY)
      require_relative "../lib/people"

      RSpec.describe People::Person, "twin" do
        it "is an adult at 19, again" do
          expect(described_class.new(19).adult?).to be(true)
        end
      end
    RUBY
  end

  def killers(run)
    mutants(run).map { |mutant| Array(mutant["killedBy"]).size }
  end

  it "stops at the first failing test without --matrix" do
    run = saboteur(dir, "--all", "--subject", subject_name)
    expect(killers(run).max).to eq(1)
    expect(run.out).not_to include("test matrix:")
  end

  it "runs every covering test per mutant, so a duplicate test is a second killer and is reported redundant" do
    run = saboteur(dir, "--all", "--matrix", "--subject", subject_name)
    expect(killers(run).max).to be >= 2
    expect(run.out).to include("test matrix:", "redundant (every kill had another killer)")
    expect(run.out).to match(%r{spec/twin_spec\.rb\[1:1\]  \d+ kills})
  end

  it "refuses to combine with --incremental" do
    run = saboteur(dir, "--all", "--matrix", "--incremental", "--subject", subject_name)
    expect(run.status).not_to eq(0)
    expect(run.err).to include("matrix cannot be combined with incremental")
  end
end
