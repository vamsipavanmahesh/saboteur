# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/pieces"

RSpec.describe Pieces::Top do
  it("reports through a transitive chain") { expect(described_class.new.report).to eq(31) }
end

RSpec.describe Pieces::Child do
  it("calls super") { expect(described_class.new.greeting).to eq("hello world") }
end

RSpec.describe Pieces::Speaker do
  it("uses the mixin") { expect(described_class.new.shout("hi")).to eq("HI!") }
end

RSpec.describe Pieces::Plain do
  it("goes through the prepended module") { expect(described_class.new.render).to eq("<x>") }
end

RSpec.describe Pieces::Delegating do
  it("forwards to the backend") { expect(described_class.new.fetch).to eq(42) }
end

RSpec.describe Pieces::Ghost do
  it("answers through method_missing") { expect(described_class.new.ghost_abc).to eq(109) }
  it("refuses other names") { expect { described_class.new.other }.to raise_error(NoMethodError) }
  it("only answers ghost names") { expect(described_class.new.respond_to?(:ghost_x)).to be(true) }
  it("does not answer other names") { expect(described_class.new.respond_to?(:zzz)).to be(false) }
end

RSpec.describe Pieces::Version do
  it("compares through Comparable") do
    expect(described_class.new(1)).to be < described_class.new(2)
    expect(described_class.new(3)).to be > described_class.new(2)
  end
end

RSpec.describe Pieces::Worker do
  it("computes inside a thread") { expect(described_class.new.compute).to eq(42) }
end

RSpec.describe Pieces::Counter do
  before(:all) { @started = Pieces::Counter.start }

  it("uses a value computed in before(:all)") { expect(@started).to eq(101) }
end

RSpec.describe Pieces::Dsl do
  it("runs a block with instance_eval") { expect(described_class.build { double(4) }).to eq(8) }
end

RSpec.describe Pieces::Lazy do
  it("calls a late-bound lambda") { expect(described_class.call(1)).to eq(1001) }
end
