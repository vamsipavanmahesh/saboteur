# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# #1290: each survivor records whether its mutated expression ever produced a
# value different from the original one (valueDiffered): false means the
# tests never varied the input across the mutation, true means the value
# changed and the tests still passed.
RSpec.describe "survivors record whether the mutated value differed", :e2e do
  let(:dir) { copy_fixture("people") }

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  def mutant(run, subject, operator, replacement)
    mutants(run).find do |m|
      m["subject"] == subject && m["mutatorName"] == operator && m["replacement"] == replacement
    end
  end

  before do
    write("lib/fee.rb", <<~RUBY)
      class Fee
        def self.for(amount) = amount < 1_000 ? 10 : amount / 100
        def self.exact(amount) = amount * 3
      end
    RUBY
    write("spec/fee_spec.rb", <<~RUBY)
      require_relative "../lib/fee"

      RSpec.describe Fee do
        it("charges the flat fee") { expect(described_class.for(500)).to eq(10) }
        it("charges a percentage") { expect(described_class.for(1_000_000)).to eq(10_000) }
        it("scales") { expect(described_class.exact(5)).to be_positive }
      end
    RUBY
  end

  it "says false where the tests never reach the boundary and true where the value changed unpinned" do
    run = saboteur(dir, "--all")

    boundary = mutant(run, "Fee.for", "comparison", "<=")
    expect(boundary).to include("status" => "Survived", "valueDiffered" => false)
    unpinned = mutant(run, "Fee.exact", "literal_number", "4")
    expect(unpinned).to include("status" => "Survived", "valueDiffered" => true)
  end

  context "with a test that stubs the mutated operator" do
    before do
      write("lib/calc.rb", <<~RUBY)
        class Calc
          def big?(meter) = meter > 5
        end
      RUBY
      write("spec/calc_spec.rb", <<~RUBY)
        require_relative "../lib/calc"

        RSpec.describe Calc do
          it "asks the operator exactly once" do
            meter = double("meter")
            expect(meter).to receive(:>).once.and_return(true)
            expect(described_class.new.big?(meter)).to be(true)
          end
        end
      RUBY
    end

    it "gives every Calc mutant the verdict an unprobed run gives it, and records nothing" do
      run = saboteur(dir, "--all")
      calc = mutants(run).select { |m| m["subject"] == "Calc#big?" }

      expect(calc).not_to be_empty
      expect(calc.map { |m| m["valueDiffered"] }.compact).to be_empty
      bumped = calc.find { |m| m["mutatorName"] == "literal_number" && m["replacement"] == "6" }
      # The stub accepts any argument and expects one call: a second
      # evaluation of the operator would kill this mutant by a verification
      # error, while an unprobed run leaves it surviving.
      expect(bumped["status"]).to eq("Survived")
    end
  end

  it "leaves killed mutants and unprobed sites without the field" do
    run = saboteur(dir, "--all")

    killed = mutants(run).select { |m| m["status"] == "Killed" }
    expect(killed).not_to be_empty
    expect(killed.map { |m| m["valueDiffered"] }.compact).to be_empty
    bare_literal = mutant(run, "Fee.for", "literal_number", "11")
    expect(bare_literal).not_to have_key("valueDiffered")
  end
end
