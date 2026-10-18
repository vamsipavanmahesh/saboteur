# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Registry DSL blocks (#700): Ohai.plugin and Puppet's provide build a class,
# class_eval the block on it and register it under a predictable constant,
# so the finder promotes their defs to subjects owned by that constant and
# re-eval redefines the methods through it. The fixture specs kill the
# mutants on the block bodies.
RSpec.describe "registry DSL subjects (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("dsl_registry")) }

  it "mutates the registry-defined methods and finishes cleanly" do
    expect(run.status).to eq(0), other_outcomes(run)
    expect(mutants(run).map { |m| m["status"] }.uniq).to eq(["Killed"])
  end

  it "names the subjects after the registered constants" do
    found = Saboteur::SubjectFinder.new.call(File.join(run.dir, "lib/plugins.rb")).subjects
    expect(found.map { |s| [s.id, s.skip_reason] }).to eq([
                                                            ["Ohai::NamedPlugin::Network#mtu_size", nil],
                                                            ["Puppet::Type::Package::ProviderPacman#hold_version", nil]
                                                          ])
  end

  it "generates mutants on the DSL block bodies only" do
    # Lines 7 and 13 are the two DSL-block method bodies; the stub lives
    # outside the mutation include.
    lines = mutants(run).map { |m| m.dig("location", "start", "line") }
    expect(lines.uniq.sort).to eq([7, 13])
  end
end
