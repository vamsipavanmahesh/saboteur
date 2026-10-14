# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe "SPDX and check-policy checks", :fixture do
  let(:base) { @base }
  let(:repository) { @fixture.repository(base: base) }
  let(:spdx) { Preflight::Checks::SpdxHeaders.new(repository: repository, head: @fixture.head) }
  let(:policy) { Preflight::Checks::CheckPolicyChanges.new(repository: repository) }

  it "passes a Ruby file with the header (valid control)" do
    @fixture.write("lib/a.rb", "# SPDX-License-Identifier: MIT\n")
    @fixture.commit("a")
    expect(spdx.call.status).to eq(:passed)
  end

  it "fails Ruby, gemspec, exe and Gemfile files without the header" do
    %w[lib/a.rb x.gemspec exe/tool Gemfile].each { |path| @fixture.write(path, "puts 1\n") }
    @fixture.commit("bare")
    expect(spdx.call.details.length).to eq(4)
  end

  it "exempts fixture projects and files that are not covered" do
    @fixture.write("spec/fixtures/projects/app/a.rb", "puts 1\n")
    @fixture.write("notes.txt", "x\n")
    @fixture.commit("exempt")
    expect(spdx.call.status).to eq(:passed)
  end

  it "ignores deleted files" do
    @fixture.write("lib/gone.rb", "# SPDX-License-Identifier: MIT\n")
    @fixture.commit("add")
    new_base = @fixture.head
    @fixture.git("rm", "-q", "lib/gone.rb")
    @fixture.commit("remove")
    result = Preflight::Checks::SpdxHeaders.new(repository: @fixture.repository(base: new_base),
                                                head: @fixture.head).call
    expect(result.status).to eq(:passed)
  end

  it "flags a change to lint policy as review-required" do
    @fixture.write(".rubocop.yml", "Layout/LineLength:\n  Max: 400\n")
    @fixture.commit("relax lint")
    expect([policy.call.status,
            policy.call.details.first]).to match([:review_required, a_string_including(".rubocop.yml")])
  end

  it "flags changes to the harness itself, its specs and mutation config" do
    %w[script/preflight_support/runner.rb spec/script/preflight/a_spec.rb config/saboteur.rb].each do |path|
      @fixture.write(path, "x\n")
    end
    @fixture.commit("harness edit")
    expect(policy.call.details.length).to eq(3)
  end

  it "passes an ordinary change" do
    @fixture.write("lib/ordinary.rb", "x\n")
    @fixture.commit("ordinary")
    expect(policy.call.status).to eq(:passed)
  end
end
