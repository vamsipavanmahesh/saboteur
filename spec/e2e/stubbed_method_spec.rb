# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Review #3, C3 (#1145): a method that is only ever stubbed has tests, but no
# test executes it. The report must claim the second, not "no tests exist".
RSpec.describe "a method exercised only through a stub (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  before do
    File.write(File.join(dir, "lib", "transfer.rb"), <<~RUBY)
      class Transfer
        def convert(amount) = amount * fx_rate

        def fx_rate
          1.5
        end
      end
    RUBY
    File.write(File.join(dir, "spec", "transfer_spec.rb"), <<~RUBY)
      require_relative "../lib/transfer"

      RSpec.describe Transfer do
        it("converts through the stubbed rate") do
          transfer = described_class.new
          allow(transfer).to receive(:fx_rate).and_return(2)
          expect(transfer.convert(10)).to eq(20)
        end
      end
    RUBY
  end

  it "says no test executes the stubbed method, never that no tests exist" do
    run = saboteur(dir, "lib/transfer.rb")

    expect(run.out).to include("1 subject not scored - no test executes it: Transfer#fx_rate")
    expect(run.out).not_to match(/no tests exist/i)
    lines = mutants(run).map { |m| m.dig("location", "start", "line") }
    expect(lines).to include(2)
    expect(lines).not_to include(4, 5)
  end
end
