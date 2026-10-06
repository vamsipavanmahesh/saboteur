# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Hooks do
  subject(:hooks) { described_class.new }

  it "runs callbacks for a hook in registration order with arguments" do
    calls = []
    hooks.register(:after_fork) { |n| calls << [:first, n] }
    hooks.register(:after_fork, ->(n) { calls << [:second, n] })

    hooks.run(:after_fork, 7)

    expect(calls).to eq([[:first, 7], [:second, 7]])
  end

  it "does nothing for a hook with no callbacks" do
    expect(hooks.run(:before_boot)).to be_nil
  end

  it "rejects unknown hook names" do
    expect { hooks.register(:before_lunch) { nil } }.to raise_error(ArgumentError, /unknown hook/)
  end

  it "rejects a registration without a callable" do
    expect { hooks.register(:after_boot) }.to raise_error(ArgumentError, /needs a callable/)
  end

  it "refuses to run around_mutant via #run" do
    expect { hooks.run(:around_mutant) }.to raise_error(ArgumentError, /#around/)
  end

  describe "#around" do
    it "nests around_mutant callbacks with the first registered outermost" do
      trace = []
      hooks.register(:around_mutant) do |mutation, inner|
        trace << [:outer_in, mutation]
        inner.call
        trace << :outer_out
      end
      hooks.register(:around_mutant) do |_mutation, inner|
        trace << :inner_in
        inner.call
        trace << :inner_out
      end

      hooks.around(:mut) { trace << :body }

      expect(trace).to eq([%i[outer_in mut], :inner_in, :body, :inner_out, :outer_out])
    end

    it "returns the block result regardless of what callbacks return" do
      hooks.register(:around_mutant) { |_m, inner| inner.call && :ignored }
      expect(hooks.around(:mut) { :result }).to eq(:result)
    end

    it "returns nil when a callback skips the chain" do
      ran = false
      hooks.register(:around_mutant) { |_m, _inner| :skipped }
      expect(hooks.around(:mut) { ran = true }).to be_nil
      expect(ran).to be(false)
    end

    it "calls the block directly when no callbacks are registered" do
      expect(hooks.around(:mut) { 42 }).to eq(42)
    end
  end
end
