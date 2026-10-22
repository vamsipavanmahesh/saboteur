# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# #1288: --color=MODE and its deprecated alias --no-color are accepted by
# every command that prints text, and a usage error names the command that
# failed, not `saboteur run`.
RSpec.describe "colour flags on every command", :e2e do
  let(:dir) { copy_fixture("people") }

  commands = [
    %w[run --list-operators], %w[pr --list-operators], %w[audit --list-operators], %w[doctor],
    %w[baseline check --baseline missing.json],
    %w[baseline propose --baseline b.json --proposal p.json --subject NoSuchKlass],
    %w[baseline accept --baseline b.json --proposal missing.json], %w[survivors], %w[explain condition_negation],
    %w[badge], %w[trend], %w[version], %w[help run], %w[help], %w[agent-skill]
  ]

  def invoke(*args)
    saboteur(dir, *args.drop(1), command: args.first)
  end

  commands.each do |command|
    ["--color=never", "--no-color"].each do |flag|
      it "accepts #{flag} after `#{command.join(' ')}`" do
        run = invoke(*command, flag)

        expect(run.err).not_to include("invalid option", "Usage: saboteur")
        expect(run.err).not_to include("unknown command", "unknown operator")
        expect(run.out + run.err).not_to match(/\e\[/)
      end
    end
  end

  it "accepts the flag before the operator for explain and before the topic for help" do
    expect(invoke("explain", "--no-color", "condition_negation").out).to include("Operator: condition_negation")
    expect(invoke("help", "--no-color", "run").out).to include("saboteur run -")
  end

  it "colours the explain output only when asked" do
    expect(invoke("explain", "--color=always", "condition_negation").out).to match(/\e\[/)
    expect(invoke("explain", "--color=never", "condition_negation").out).not_to match(/\e\[/)
  end

  [%w[doctor], %w[baseline check], %w[badge], %w[trend]].each do |command|
    it "prints the #{command.join(' ')} usage line for a bad option" do
      run = invoke(*command, "--bogus")

      expect(run.status).to eq(2)
      expect(run.err).to include("Usage: saboteur #{command.first}")
      expect(run.err).not_to include("Usage: saboteur run")
    end
  end
end
