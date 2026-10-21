# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# #387: a suite that connects ActiveRecord to sqlite :memory: and loads its
# schema at require time loses the schema in saboteur's forked children, and
# the bare "Could not find table" failure sends the user debugging a suite
# that is green under plain rspec. The baseline refusal must name the cause
# and the remedies - and the remedies must actually work.
RSpec.describe "sqlite :memory: schema loaded at require time (#387)", :e2e do
  let(:dir) { copy_fixture("memorydb") }

  it "refuses the baseline with the fork-empty-database cause and the remedies" do
    run = saboteur(dir, "--all")
    expect(run.status).to eq(5)
    expect(run.err).to include("baseline check")
    expect(run.err).to include(":memory:")
    expect(run.err).to include("before(:suite)")
    expect(run.err).to include("after_fork")
  end

  it "passes the baseline once the schema moves into before(:suite), as the hint advises" do
    helper = File.join(dir, "spec", "spec_helper.rb")
    source = File.read(helper)
    schema = <<~RUBY
      ActiveRecord::Schema.verbose = false
      ActiveRecord::Schema.define do
        create_table :widgets do |table|
          table.integer :number
        end
      end
    RUBY
    before_suite = <<~RUBY
      RSpec.configure do |config|
        config.before(:suite) do
    RUBY
    indented = schema.lines.map { |line| "    #{line}" }.join
    File.write(helper, source.sub("ActiveRecord::Schema.define do\n  " \
                                  "create_table :widgets do |table|\n    " \
                                  "table.integer :number\n  " \
                                  "end\n" \
                                  "end\n", "#{before_suite}#{indented}  end\nend\n"))

    run = saboteur(dir, "--all")
    expect(run.status).to eq(0)
    expect(run.err).to include("baseline check 1 took")
  end
end
