# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "saboteur run (end to end)", :e2e do
  describe "the adult? example" do
    let(:dir) { copy_fixture("people") }

    def adult_comparison(run, replacement)
      mutants(run).find do |m|
        m["mutatorName"] == "comparison" && m["replacement"] == replacement && m["location"]["start"]["line"] == 14
      end
    end

    it "lets >= -> > survive with tests at 17 and 19, and kills it once 18 is tested" do
      first = saboteur(dir)
      expect(first.status).to eq(1), first.err
      expect(adult_comparison(first, ">")["status"]).to eq("Survived")
      expect(first.out).to include("-    def adult?; @age >= 18; end", "+    def adult?; @age > 18; end")

      File.write(File.join(dir, "spec", "boundary_spec.rb"), <<~RUBY)
        require_relative "../lib/people"

        RSpec.describe People::Person do
          it "is an adult at exactly 18" do
            expect(described_class.new(18).adult?).to be(true)
          end
        end
      RUBY
      second = saboteur(dir)
      expect(adult_comparison(second, ">")["status"]).to eq("Killed")
      expect(test_names(second, adult_comparison(second, ">")["killedBy"])).to eq(["./spec/boundary_spec.rb[1:1]"])
    end

    it "skips subjects whose neutral check fails instead of reporting killed (class_eval constant scope)" do
      run = saboteur(dir)
      constant_mutants = mutants(run).select { |m| m["location"]["start"]["line"].between?(16, 18) }
      expect(constant_mutants.map { |m| m["status"] }.uniq).to eq(["Ignored"])
      expect(constant_mutants.map { |m| m["statusReason"] }.uniq).to eq(["baseline failure"])
      expect(run.out).to include("People::Person#adult_by_constant?: neutral check killed")
    end

    it "runs those subjects with the nesting strategy" do
      run = saboteur(dir, "--reeval", "nesting")
      constant_mutants = mutants(run).select { |m| m["location"]["start"]["line"].between?(16, 18) }
      expect(constant_mutants.map { |m| m["status"] }).not_to include("Ignored")
    end

    it "reuses the cached coverage map on the second run" do
      saboteur(dir)
      second = saboteur(dir)
      expect(second.err).not_to include("building coverage map")
      expect(Dir.glob(File.join(dir, ".saboteur", "coverage-*.json")).size).to eq(1)
    end

    it "reports mutants in a branch no test executes as no coverage, not as survivors" do
      run = saboteur(dir, "--subject", "Stage")
      child_branch = mutants(run).select { |m| m["location"]["start"]["line"].between?(9, 10) }
      expect(child_branch).not_to be_empty
      expect(child_branch.map { |m| m["status"] }.uniq).to eq(["NoCoverage"])
    end

    it "runs the fastest covering test first, so it is the one that kills" do
      run = saboteur(dir, "--subject", "Stage")
      killed = mutants(run).select { |m| m["status"] == "Killed" }
      expect(killed).not_to be_empty
      expect(killed.map { |m| test_names(run, m["killedBy"]) }.uniq).to eq([["./spec/stage_spec.rb[1:1]"]])
    end

    it "tells assertion kills from crash kills through real RSpec" do
      run = saboteur(dir, "--subject", "People::Person#adult?")
      by_operator = mutants(run).to_h { |m| [m["mutatorName"], m["statusReason"]] }
      expect(by_operator.values_at("body_nil", "body_raise")).to eq(["assertion", "crash: RuntimeError"])
      expect(run.out).to include("kills:", "by a crash (RuntimeError 1)")
    end

    it "runs only the selected subject" do
      run = saboteur(dir, "--subject", "People::Person#describe")
      expect(mutants(run).map { |m| m["location"]["start"]["line"] }.uniq).to eq([21])
    end
  end

  describe "hazardous mutants" do
    let(:dir) { copy_fixture("hazards") }
    let(:run) { saboteur(dir) }

    def status_of(operator)
      mutants(run).find { |m| m["mutatorName"] == "hazard_#{operator}" }&.fetch("status")
    end

    it "times out a hanging mutant and kills the grandchild it started" do
      expect(status_of("spin")).to eq("Timeout")
      pid = File.read(File.join(dir, "grandchild.pid")).to_i
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      alive = lambda do
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end
      sleep 0.05 while alive.call && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      expect(alive.call).to be(false)
    end

    it "reports a child that crashes during its tests as error, not killed" do
      expect(status_of("crash_in_test")).to eq("RuntimeError")
    end

    it "reports a child that fails while loading the mutant as error, not killed" do
      expect(status_of("raise_on_load")).to eq("RuntimeError")
      expect(status_of("die_on_load")).to eq("RuntimeError")
      expect(run.out).to include("broken mutant", "killed by signal 9 before tests")
    end

    it "kills a mutant of a private method, which stays private after re-evaluation" do
      # The spec asserts `secret` is private; if re-evaluation made it public,
      # the neutral check would fail and the mutant would be skipped.
      expect(status_of("secret")).to eq("Killed")
      killed_by = mutants(run).find { |m| m["mutatorName"] == "hazard_secret" }["killedBy"]
      expect(test_names(run, killed_by)).to eq(["./spec/hazards_spec.rb[1:5]"])
    end

    it "exits 0 with no survivors, even with errors and timeouts" do
      expect(run.status).to eq(0)
      expect(run.out).to include("killed 1  survived 0  timeout 1  error 3  skipped 0")
    end
  end
end
