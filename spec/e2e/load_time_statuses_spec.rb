# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "load-time statuses (end to end)", :e2e do
  describe "code that only ran while the app loaded (issue #105)" do
    it "marks those mutants ran at load: out of the score, with a hint, and no survivors" do
      run = saboteur(copy_fixture("loadtime"))
      expect(run.status).to eq(0), run.err
      at_load = mutants(run).select { |m| m["statusReason"].to_s.start_with?("ran at load:") }
      expect(at_load).not_to be_empty
      expect(at_load.map { |m| m["status"] }.uniq).to eq(["Ignored"])
      unignored = mutants(run).reject { |m| m["statusReason"].to_s.start_with?("ignored:") }
      expect(unignored.map { |m| m["status"] }).not_to include("Survived")
      size_mutants = mutants(run).select { |m| m.dig("location", "start", "line") == 23 }
      expect(size_mutants.map { |m| m["status"] }.uniq).to eq(["Killed"])
      expect(run.out).to include("Ran at load (out of the score):", "ran at load:")
      verbose_run = saboteur(copy_fixture("loadtime"), "--verbose")
      expect(verbose_run.out).to include("Hooks.label_for", "Hooks.included")
    end
  end

  describe "a method a captured Method object still calls in its original form (issue #106)" do
    it "marks its mutants unreachable with the capture site, while a late-bound caller is judged normally" do
      run = saboteur(copy_fixture("captured"))
      min_mutants = mutants(run).select { |m| m["location"]["start"]["line"].between?(4, 6) }
      expect(min_mutants).not_to be_empty
      expect(min_mutants.map { |m| m["status"] }.uniq).to eq(["Ignored"])
      expect(min_mutants.map { |m| m["statusReason"] }.uniq.first)
        .to match(/captured before re-evaluation.*limits\.rb:5/)
      max_mutants = mutants(run).select { |m| m["location"]["start"]["line"].between?(8, 10) }
      expect(max_mutants).not_to be_empty
      expect(max_mutants.map { |m| m["status"] }.uniq).to eq(["Killed"])
      expect(run.out).to include("Unreachable (out of the score):")
    end
  end

  describe "a sorbet sig-wrapped method (issue #104)" do
    it "mutates it like its untyped twin instead of skipping it as shadowed" do
      run = saboteur(copy_fixture("sorbet"))
      typed = mutants(run).select { |m| m["location"]["start"]["line"].between?(10, 12) }
      untyped = mutants(run).select { |m| m["location"]["start"]["line"].between?(14, 16) }
      expect(typed).not_to be_empty
      # The shim preserves wrappers but does not check types. Signature text
      # must not hide nil mutants that the fixture's assertions really kill.
      expect(typed.map { |m| m["mutatorName"] }).to eq(untyped.map { |m| m["mutatorName"] })
      expect(typed.map { |m| m["mutatorName"] }.count("body_nil")).to eq(1)
      expect(typed.map { |m| m["status"] }).to eq(untyped.map { |m| m["status"] })
      expect(typed.map { |m| m["status"] }.uniq).to eq(["Killed"])
      expect(run.out).not_to include("shadowed definition")
    end
  end
end
