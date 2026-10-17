# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The defined-order prefix (#557) rebuilds the slice of a file that must run
# before a covering example: from the file's first example through the last
# covering one, positions compared as numbers. A prefix that adds nothing to
# the covering examples, or one that cannot be parsed, is no retry at all.
RSpec.describe Saboteur::Engine::DefinedOrderPrefix do
  subject(:prefix) { described_class.new(every_test) }

  let(:every_test) do
    ["./spec/a_spec.rb[1:1]", "./spec/a_spec.rb[1:2]", "./spec/a_spec.rb[1:3]",
     "./spec/b_spec.rb[1:1]", "./spec/b_spec.rb[1:2]", "./spec/b_spec.rb[1:10]"]
  end

  it "runs through the last covering example of each file, not the first" do
    expect(prefix.for(["./spec/a_spec.rb[1:2]", "./spec/a_spec.rb[1:3]"]))
      .to eq(["./spec/a_spec.rb[1:1]", "./spec/a_spec.rb[1:2]", "./spec/a_spec.rb[1:3]"])
  end

  it "orders example positions numerically, so [1:10] sorts after [1:2]" do
    expect(prefix.for(["./spec/b_spec.rb[1:10]"]))
      .to eq(["./spec/b_spec.rb[1:1]", "./spec/b_spec.rb[1:2]", "./spec/b_spec.rb[1:10]"])
  end

  it "returns nil when any covering id is not an RSpec id, even if the others parse" do
    expect(prefix.for(["./spec/a_spec.rb[1:2]", "not-an-rspec-id"])).to be_nil
  end

  it "returns nil when the prefix adds nothing to the covering examples" do
    expect(prefix.for(["./spec/a_spec.rb[1:1]", "./spec/a_spec.rb[1:2]"])).to be_nil
  end
end
