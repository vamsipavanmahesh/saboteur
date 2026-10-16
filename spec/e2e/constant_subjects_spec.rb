# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

RSpec.describe "constant literal subjects in --since mode (issue #306)", :e2e do
  # The fixture's spec is the BASE version: the run below commits it, then
  # adds entries to the constant hash and array plus specs observing them.
  def commit(dir)
    system("git", "init", "-q", dir, exception: true)
    system("git", "-C", dir, "add", ".", exception: true)
    system("git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.com",
           "commit", "-q", "-m", "base", exception: true)
  end

  it "mutates changed hash entries and array elements, killed only where a spec observes the read" do
    dir = copy_fixture("constants")
    commit(dir)

    lib = File.join(dir, "lib", "rules.rb")
    File.write(lib, File.read(lib)
      .sub("    zip: \"optional\"\n", "    zip: \"optional\",\n    state: \"optional\",\n    country: \"optional\"\n")
      .sub("%w[alpha beta]", "%w[alpha beta gamma]"))
    spec = File.join(dir, "spec", "rules_spec.rb")
    text = File.read(spec)
    insert = <<~RUBY
      it "marks a state optional" do
        expect(described_class.rule_for(:state)).to eq("optional")
      end

      it "knows the gamma tag" do
        expect(described_class.tagged?("gamma")).to be(true)
      end
    RUBY
    File.write(spec, text.sub(/end\n\z/, "#{insert}end\n"))

    # Survivors mean a reviewable exit: the added `country` entry and the
    # `beta` tag have no observing spec, so their removals survive.
    run = saboteur(dir, "--since", "HEAD", "--agent")
    expect(run.status).to eq(1), run.err
    by = mutants(run).group_by { |m| m.fetch("mutatorName") }

    # The hash entries live on their own lines; the %w tags share one line.
    pair_lines = by.fetch("pair_removal").map { |m| m["location"]["start"]["line"] }
    expect(by.fetch("pair_removal").map { |m| m.fetch("status") }).to include("Killed", "Survived")
    expect(by.fetch("element_removal").map { |m| m.fetch("status") }).to include("Killed", "Survived")
    expect(pair_lines).to include(8, 9) # the added state and country entries
    expect(pair_lines).not_to include(6) # the unchanged zip entry stays out of scope
  end

  # A spec can read the constant with no method in between: its line hit
  # must still map the mutant to that spec (#319).
  it "kills a constant mutant a spec observes by reading the constant directly" do
    dir = copy_fixture("constants")
    commit(dir)

    lib = File.join(dir, "lib", "rules.rb")
    File.write(lib, File.read(lib).sub("    zip: \"optional\"\n", "    zip: \"optional\",\n    state: \"enabled\"\n"))
    spec = File.join(dir, "spec", "rules_spec.rb")
    insert = <<~RUBY
      it "reads the map directly" do
        expect(Rules::MAP[:state]).to eq("enabled")
      end
    RUBY
    File.write(spec, File.read(spec).sub(/end\n\z/, "#{insert}end\n"))

    run = saboteur(dir, "--since", "HEAD", "--agent")
    expect(run.status).to eq(0), run.err
    # The zip line gains the comma, so its pair is in scope too; both
    # removals die - zip through the method read, state through the spec's
    # direct read of the constant.
    pairs = mutants(run).select { |m| m["mutatorName"] == "pair_removal" }
    expect(pairs.map { |m| m["status"] }).to eq(%w[Killed Killed])
    expect(pairs.flat_map { |m| m["killedBy"] }).not_to be_empty
  end

  it "mutates nothing when only the constant's comment changed" do
    dir = copy_fixture("constants")
    commit(dir)
    lib = File.join(dir, "lib", "rules.rb")
    File.write(lib, File.read(lib).sub("    zip: \"optional\"\n", "    zip: \"optional\" # note\n"))

    run = saboteur(dir, "--since", "HEAD", "--agent")
    expect(mutants(run)).to be_empty
    expect(run.err).to include("Rules::MAP", "differ only in comments or formatting")
  end

  it "reports an unsupported changed constant instead of mutating it" do
    dir = copy_fixture("constants")
    commit(dir)
    lib = File.join(dir, "lib", "rules.rb")
    File.write(lib, "#{File.read(lib)}\nLIMIT = 10\n")
    system("git", "-C", dir, "add", ".", exception: true)
    system("git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.com",
           "commit", "-q", "-m", "limit", exception: true)
    File.write(lib, File.read(lib).sub("LIMIT = 10", "LIMIT = 20"))

    run = saboteur(dir, "--since", "HEAD", "--agent")
    expect(mutants(run)).to be_empty
    expect(run.json.fetch("warnings").join).to include("changed constant LIMIT", "not a hash or array literal")
  end
end
