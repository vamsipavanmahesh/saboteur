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
