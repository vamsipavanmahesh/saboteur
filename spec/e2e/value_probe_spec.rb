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

  it "labels the boundary survivor input_gap and the be_positive survivor assertion_gap (#1290)" do
    run = saboteur(dir, "--all")

    expect(mutant(run, "Fee.for", "comparison", "<=")).to include("classification" => "input_gap")
    expect(mutant(run, "Fee.exact", "literal_number", "4")).to include("classification" => "assertion_gap")
    expect(run.out).to include("[input_gap]").or include("input_gap")
  end

  it "keeps the observation and the labels when the second run replays cached verdicts (#1290)" do
    saboteur(dir, "--all")
    run = saboteur(dir, "--all")

    expect(mutant(run, "Fee.for", "comparison", "<=")).to include("valueDiffered" => false,
                                                                  "classification" => "input_gap")
    expect(mutant(run, "Fee.exact", "literal_number", "4")).to include("valueDiffered" => true,
                                                                       "classification" => "assertion_gap")
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

    it "gives every Calc mutant the verdict an unprobed run gives it, and reports an explicit null (#1311)" do
      run = saboteur(dir, "--all")
      calc = mutants(run).select { |m| m["subject"] == "Calc#big?" }

      expect(calc).not_to be_empty
      expect(calc).to all(include("valueDiffered" => nil))
      bumped = calc.find { |m| m["mutatorName"] == "literal_number" && m["replacement"] == "6" }
      # The stub accepts any argument and expects one call: a second
      # evaluation of the operator would kill this mutant by a verification
      # error, while an unprobed run leaves it surviving.
      expect(bumped["status"]).to eq("Survived")
    end
  end

  context "when only a confirmation spec gives the mutant a differing input (#1311)" do
    def git(*args)
      _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com",
                                         *args, chdir: dir)
      raise err unless status.success?
    end

    before do
      write("config/saboteur.rb", <<~RUBY)
        Saboteur.configure do |c|
          c.confirmation_budget = 300
        end
      RUBY
      write("lib/ledger/fx.rb", <<~RUBY)
        module Ledger
          class Fx
            def self.convert(a) = 83 * a
          end
        end
      RUBY
      write("spec/ledger/fx_spec.rb", <<~RUBY)
        require_relative "../../lib/ledger/fx"

        RSpec.describe Ledger::Fx do
          it("converts zero") { expect(described_class.convert(0)).to eq(0) }
        end
      RUBY
      write("spec/integration/fx_flow_spec.rb", <<~RUBY)
        require_relative "../../lib/ledger/fx"

        RSpec.describe "fx flow" do
          it("stays positive") { expect(Ledger::Fx.convert(10)).to be > 0 }
        end
      RUBY
      git("init", "-q")
      git("add", ".")
      git("commit", "-q", "-m", "base")
      write("lib/ledger/fx.rb", File.read(File.join(dir, "lib/ledger/fx.rb")).sub("83 * a", "a * 83"))
      saboteur(dir, "--all")
    end

    it "labels the confirmed survivor assertion_gap with valueDiffered true" do
      run = saboteur(dir, "--since", "HEAD")

      mutant = mutant(run, "Ledger::Fx.convert", "literal_number", "84")
      expect(mutant).to include("status" => "Survived", "confirmation" => "confirmed",
                                "valueDiffered" => true, "classification" => "assertion_gap")
      expect(run.out).to include("a test ran this mutant, the value changed, and no assertion noticed")
    end
  end

  it "reports a kill true when the value differed before its assertion fired, never false (#1311)" do
    run = saboteur(dir, "--all")

    killed = mutants(run).select { |m| m["status"] == "Killed" }
    expect(killed).not_to be_empty
    expect(killed.map { |m| m["valueDiffered"] }.compact).to all(be(true))
    # A bare edited literal is never probed (its difference is by construction),
    # so its assertion kill reports null, never false.
    bare_literal = mutant(run, "Fee.for", "literal_number", "11")
    expect(bare_literal).to include("status" => "Killed", "valueDiffered" => nil)
    # A probed arithmetic site killed by its assertion keeps the true observation.
    percentage = mutant(run, "Fee.for", "arithmetic", "*")
    expect(percentage).to include("status" => "Killed", "valueDiffered" => true)
  end
end
