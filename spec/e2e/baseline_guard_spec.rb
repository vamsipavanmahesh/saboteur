# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "baseline stability guard", :e2e do
  def write_suite(directory, body)
    File.write(File.join(directory, "spec/person_spec.rb"), "require_relative \"../lib/people\"\n#{body}")
  end

  it "refuses a failing suite before producing mutant results" do
    directory = copy_fixture("people")
    write_suite(directory, <<~RUBY)
      RSpec.describe People::Person do
        it("fails unchanged") { expect(true).to be(false) }
      end
    RUBY
    run = saboteur(directory, "--all", "--seed", "42")
    expect(run.status).to eq(5)
    expect(run.json).to be_nil
    expect(run.err).to include("baseline check 1 failed at seed 42", "Fix the suite", "No mutants were started")
    log = File.read(File.join(directory, ".saboteur/baseline-1.log"))
    expect(log).to include("fails unchanged", "expected", "examples finished", "1 failure")
  end

  it "puts a suite-hook failure's detail in the phase log" do
    directory = copy_fixture("people")
    write_suite(directory, <<~RUBY)
      RSpec.configure { |config| config.before(:suite) { raise "hook exploded" } }
      RSpec.describe People::Person do
        it("runs") { expect(true).to be(true) }
      end
    RUBY
    run = saboteur(directory, "--all", "--seed", "42")
    expect(run.status).to eq(5)
    log = File.read(File.join(directory, ".saboteur/baseline-1.log"))
    expect(log).to include("hook exploded")
  end

  it "detects a second-check failure in a separate child" do
    directory = copy_fixture("people")
    write_suite(directory, <<~RUBY)
      RSpec.describe People::Person do
        it "changes between processes" do
          path = "baseline-counter"
          count = File.exist?(path) ? File.read(path).to_i : 0
          File.write(path, count + 1)
          expect(count).to eq(0)
        end
      end
    RUBY
    run = saboteur(directory, "--all", "--seed", "17")
    expect(run.status).to eq(5)
    expect(run.err).to include("baseline check 2 failed at seed 17")
    expect(File.read(File.join(directory, "baseline-counter"))).to eq("2")
    expect(run.json).to be_nil
  end

  it "checks even when a coverage cache already exists" do
    directory = copy_fixture("people")
    write_suite(directory, <<~RUBY)
      RSpec.describe People::Person do
        it "can fail without a test-file edit" do
          expect(ENV["FAIL_BASELINE"]).to be_nil
        end
      end
    RUBY
    cached_run = saboteur(directory, "--all", "--seed", "19", "--incremental")
    expect(cached_run.json).not_to be_nil, "#{cached_run.err}\n#{cached_run.out}"
    cached_paths = Dir[File.join(directory, ".saboteur/coverage-*.json")]
    expect(cached_paths).not_to be_empty
    original_bytes = cached_paths.to_h { |path| [path, File.binread(path)] }
    run = saboteur(directory, "--all", "--seed", "19", "--incremental", env: { "FAIL_BASELINE" => "1" })
    expect(original_bytes.transform_values { |bytes| bytes }).to eq(
      cached_paths.to_h { |path| [path, File.binread(path)] }
    )
    expect(run.status).to eq(5)
    expect(run.json).to be_nil
    expect(run.err).to include("baseline check 1 failed at seed 19")
  end

  it "refuses a coverage pass that fails after both baseline checks passed" do
    directory = copy_fixture("people")
    write_suite(directory, <<~RUBY)
      RSpec.describe People::Person do
        it "fails on the third whole-suite run" do
          path = "whole-suite-counter"
          count = File.exist?(path) ? File.read(path).to_i : 0
          File.write(path, count + 1)
          expect(count).to be < 2
        end
      end
    RUBY
    run = saboteur(directory, "--all", "--seed", "23")
    # Coverage-build failures still exit 3; routing them to 5 via a
    # BaselineRedError subclass is a tracked follow-up.
    expect(run.status).to eq(3)
    expect(run.json).to be_nil
    expect(run.err).to include("unchanged suite failed while building coverage", "Fix the suite", "seed 23")
    expect(Dir[File.join(directory, ".saboteur/coverage-*.json")]).to be_empty
  end

  it "accepts pending and skipped examples and uses one seeded order for coverage" do
    directory = copy_fixture("people")
    write_suite(directory, <<~RUBY)
      RSpec.describe People::Person do
        5.times do |number|
          it "records example \#{number}" do
            File.open("suite-orders", "a") { |file| file.puts(number) }
          end
        end
        xit("is skipped") { raise "should not execute" }
        it("is pending") { pending "not implemented"; expect(1).to eq(2) }
      end
    RUBY
    run = saboteur(directory, "--all", "--seed", "123")
    expect(run.json).not_to be_nil, "#{run.err}\n#{run.out}"
    order = File.read(File.join(directory, "suite-orders")).lines.map(&:strip)
    expect(order.size).to eq(15)
    expect(order.each_slice(5).to_a.uniq.size).to eq(1)
  end

  it "keeps suite hooks at the run seed with conflicting configured RSpec order" do
    directory = copy_fixture("people")
    File.write(File.join(directory, "config", "saboteur.rb"), <<~RUBY)
      Saboteur.configure do |c|
        c.include = ["lib/**/*.rb"]
        c.rspec_args = ["--seed", "999", "spec"]
      end
    RUBY
    write_suite(directory, <<~RUBY)
      RSpec.configure do |configuration|
        configuration.before(:suite) do
          raise "wrong suite seed" unless RSpec.configuration.seed == 123
        end
      end
      RSpec.describe People::Person do
        it("checks an adult") { expect(described_class.new(19).adult?).to be(true) }
        it("checks a child") { expect(described_class.new(17).adult?).to be(false) }
      end
    RUBY
    run = saboteur(directory, "--all", "--seed", "123", "--subject", "People::Person#adult?")
    expect(run.json).not_to be_nil, "#{run.err}\n#{run.out}"
    expect(mutants(run).map { |entry| entry["status"] }).to include("Killed")
    expect(mutants(run).map { |entry| entry["status"] }).not_to include("RuntimeError")
  end

  it "sets Ruby randomness and RSpec order from the run seed" do
    directory = copy_fixture("people")
    write_suite(directory, <<~RUBY)
      RSpec.describe People::Person do
        it "uses the run seed" do
          expect(RSpec.configuration.seed).to eq(123)
          expect(rand).to eq(Random.new(123).rand)
        end
      end
    RUBY
    run = saboteur(directory, "--all", "--seed", "123")
    expect(run.json).not_to be_nil
    expect(run.err).not_to include("baseline check 1 failed", "baseline check 2 failed")
  end
end
