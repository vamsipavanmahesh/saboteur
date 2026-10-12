# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "coarse and fine execution", :e2e do
  let(:dir) { copy_fixture("people") }

  before do
    File.open(File.join(dir, "lib/people.rb"), "a") do |file|
      file.puts "class CoarseProbe; def value(a); a + 1; end; end"
    end
    File.write(File.join(dir, "spec/probe_spec.rb"), <<~RUBY)
      require_relative "../lib/people"
      RSpec.describe CoarseProbe do
        it("returns without error") { expect { CoarseProbe.new.value(2) }.not_to raise_error }
      end
    RUBY
  end

  def verdicts(run)
    mutants(run).to_h { |item| [item.fetch("id"), item.fetch("status")] }
  end

  it "runs fine mutants after a nil survivor with serial/parallel and fresh/all-cache parity" do
    serial = saboteur(dir, "--subject", "CoarseProbe#value", "--jobs", "1", "--incremental")
    expect(mutants(serial).find { |item| item["mutatorName"] == "body_nil" }.fetch("status")).to eq("Survived")
    fine = mutants(serial).reject { |item| item["mutatorName"].start_with?("body_") }
    expect(fine).not_to be_empty
    expect(fine.map { |item| item["status"] }).not_to include("Ignored", "NoCoverage")
    cached = saboteur(dir, "--subject", "CoarseProbe#value", "--jobs", "2", "--incremental")
    expect(verdicts(cached)).to eq(verdicts(serial))
    expect(cached.out).to include("reused")
    parallel = saboteur(dir, "--subject", "CoarseProbe#value", "--jobs", "2")
    expect(verdicts(parallel)).to eq(verdicts(serial))
  end

  it "includes killed fine mutants even if removing the entire body survives" do
    # The test permits nil but detects a changed calculation for normal inputs.
    File.write(File.join(dir, "spec/probe_spec.rb"), <<~RUBY)
      require_relative "../lib/people"
      RSpec.describe CoarseProbe do
        it("permits an absent value, otherwise preserves its result") do
          result = CoarseProbe.new.value(2)
          expect(result).to eq(3) unless result.nil?
        end
      end
    RUBY
    run = saboteur(dir, "--subject", "CoarseProbe#value")
    expect(mutants(run).find { |item| item["mutatorName"] == "body_nil" }.fetch("status")).to eq("Survived")
    fine = mutants(run).reject { |item| item["mutatorName"].start_with?("body_") }
    expect(fine.map { |item| item["status"] }).to include("Killed")
  end
end
