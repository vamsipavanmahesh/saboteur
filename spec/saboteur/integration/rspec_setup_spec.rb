# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rspec/core"

RSpec.describe Saboteur::Integration::RSpec, "#setup" do
  def integration
    described_class.new(Saboteur::Config.new({}, root: Dir.pwd))
  end

  def stub_runner_setup(error)
    runner = instance_double(RSpec::Core::Runner)
    allow(RSpec::Core::Runner).to receive(:new).and_return(runner)
    allow(runner).to receive(:setup).and_raise(error)
  end

  # A spec file calling exit at load makes RSpec print "While loading
  # <file> ..." and re-raise SystemExit through Runner#setup. Uncaught, the
  # parent would exit with the spec's status: exit(0) ends the run
  # silently green without mutating anything (#411).
  it "refuses the run when a spec file calls exit(0) at load time" do
    stub_runner_setup(SystemExit.new(0))
    expect { integration.setup }.to raise_error(Saboteur::Error, /called exit.*status 0/)
  end

  it "refuses the run when a spec file calls exit with a failure status" do
    stub_runner_setup(SystemExit.new(3))
    expect { integration.setup }.to raise_error(Saboteur::Error, /called exit.*status 3/)
  end
end

RSpec.describe Saboteur::Integration::RSpec, "Coverage double-start hint (#645)" do
  # The audited repro: single_cov's unguarded `SingleCov.setup :rspec` at
  # spec_helper.rb:4 collides with saboteur's own Coverage.start, and rspec
  # prints the RuntimeError inside its load-failure report before quitting.
  def refusal_for(load_lines)
    runner = instance_double(RSpec::Core::Runner)
    allow(RSpec::Core::Runner).to receive(:new).and_return(runner)
    allow(runner).to receive(:setup) do |_err, out|
      load_lines.each { |line| out.puts line }
    end
    # #756: with the runner stubbed benign, setup reaches
    # `configuration.order = "rand:1"` on the global ::RSpec.configuration
    # before the quit path raises; unstubbed, that rewrites the live suite's
    # seed and the run's closing banner reports "Randomized with seed 1".
    allow(RSpec.configuration).to receive(:order=)
    integration = described_class.new(Saboteur::Config.new({}, root: Dir.pwd))
    world = Struct.new(:wants_to_quit).new(true)
    allow(integration).to receive(:world).and_return(world)
    expect { integration.setup }.to raise_error(Saboteur::Error) { |error| @message = error.message }
    @message
  end

  it "suspects the suite's own Coverage and names both guard styles" do
    message = refusal_for([
                            "An error occurred while loading ./spec/spec_helper.rb.",
                            "RuntimeError: coverage measurement is already setup " \
                            "(single_cov-2.1.0/lib/single_cov.rb:257 Coverage.start, ./spec/spec_helper.rb:4)",
                            "No examples found."
                          ])
    expect(message).to include("./spec/spec_helper.rb")
    expect(message).to match(/suspect: your suite starts its own Coverage/i)
    expect(message).to include('ENV["COVERAGE"]', "SingleCov")
    expect(message).to include("docs/recipes/README.md#simplecov")
  end

  it "suspects Coverage from a simplecov backtrace line alone" do
    message = refusal_for([
                            "An error occurred while loading ./spec/spec_helper.rb.",
                            "  .simplecov:2: SimpleCov.start",
                            "No examples found."
                          ])
    expect(message).to match(/suspect: your suite starts its own Coverage/i)
  end

  it "does not suspect Coverage from a spec file NAME that merely mentions simplecov" do
    message = refusal_for([
                            "An error occurred while loading ./spec/simplecov_config_spec.rb.",
                            "NameError: uninitialized constant SimplecovConfig",
                            "No examples found."
                          ])
    expect(message).not_to include("Suspect")
    expect(message).to include("rspec quit while loading spec files", "simplecov_config_spec.rb")
  end

  it "keeps the #378 wording whole for an unrelated load failure (no Coverage suspect)" do
    message = refusal_for([
                            "An error occurred while loading ./spec/models/user_spec.rb.",
                            "No examples found."
                          ])
    expect(message).not_to match(/suspect: your suite starts its own Coverage/i)
    expect(message).to include("rspec quit while loading spec files", "user_spec.rb",
                               "Exclude the broken subtrees")
  end
end
