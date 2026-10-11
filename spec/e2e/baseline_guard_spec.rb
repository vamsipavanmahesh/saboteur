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
    run = saboteur(directory, "--seed", "42")
    expect(run.status).to eq(3)
    expect(run.json).to be_nil
    expect(run.err).to include("baseline check 1 failed at seed 42", "Fix the suite", "No mutants were started")
    expect(File).to exist(File.join(directory, ".saboteur/baseline-1.log"))
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
    run = saboteur(directory, "--seed", "17")
    expect(run.status).to eq(3)
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
    cached_run = saboteur(directory, "--seed", "19", "--incremental")
    expect(cached_run.json).not_to be_nil, "#{cached_run.err}\n#{cached_run.out}"
    cached_paths = Dir[File.join(directory, ".saboteur/coverage-*.json")]
    expect(cached_paths).not_to be_empty
    original_bytes = cached_paths.to_h { |path| [path, File.binread(path)] }
    run = saboteur(directory, "--seed", "19", "--incremental", env: { "FAIL_BASELINE" => "1" })
    expect(original_bytes.transform_values { |bytes| bytes }).to eq(
      cached_paths.to_h { |path| [path, File.binread(path)] }
    )
    expect(run.status).to eq(3)
    expect(run.json).to be_nil
    expect(run.err).to include("baseline check 1 failed at seed 19")
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
    run = saboteur(directory, "--seed", "123")
    expect(run.json).not_to be_nil
    expect(run.err).not_to include("baseline check 1 failed", "baseline check 2 failed")
  end
end
