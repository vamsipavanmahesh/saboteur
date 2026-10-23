# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Models the README "Know the limits" claim "RSpec-only ... no Minitest":
# a project whose only tests are Minitest gets a clear refusal, not a
# silently empty run.
RSpec.describe "a project with only a Minitest suite (end to end)", :e2e do
  it "refuses with exit 2 and points at docs/minitest.md" do
    dir = copy_fixture("people")
    Dir.glob(File.join(dir, "spec", "*_spec.rb")).each { |spec| FileUtils.rm(spec) }
    FileUtils.mkdir_p(File.join(dir, "test"))
    File.write(File.join(dir, "test", "people_test.rb"), <<~RUBY)
      require "minitest/autorun"
      require_relative "../lib/people"

      class PeopleTest < Minitest::Test
        def test_adult
          assert People::Person.new(18).adult?
        end
      end
    RUBY
    run = saboteur(dir)
    expect(run.status).to eq(2)
    expect(run.err).to include("no RSpec suite found", "docs/minitest.md")
  end
end
