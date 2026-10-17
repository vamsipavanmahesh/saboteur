# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Integration::RSpec, "with rspec-core missing (#482)" do
  let(:integration) { described_class.new(Saboteur::Config.new({}, root: Dir.pwd)) }

  def without_rspec_core
    load_error = LoadError.new("cannot load such file -- rspec/core")
    allow(load_error).to receive(:path).and_return("rspec/core")
    allow(integration).to receive(:require).and_raise(load_error)
    yield
  end

  it "refuses setup with the remedy instead of crashing into the internal-error report" do
    without_rspec_core do
      expect { integration.setup }.to raise_error(Saboteur::Error, /rspec is not in the bundle.*test group/m)
    end
  end

  it "refuses configured_spec_files the same way" do
    without_rspec_core do
      expect { integration.configured_spec_files(Dir.pwd) }.to raise_error(Saboteur::Error, /rspec is not in the bundle/)
    end
  end

  it "re-raises a LoadError for any other file, keeping the crash route" do
    load_error = LoadError.new("cannot load such file -- the_app/boot")
    allow(load_error).to receive(:path).and_return("the_app/boot")
    allow(integration).to receive(:require).and_raise(load_error)
    expect { integration.setup }.to raise_error(LoadError, /the_app\/boot/)
  end

  it "re-raises a LoadError for rspec/core_ext: the message matches, the feature does not" do
    load_error = LoadError.new("cannot load such file -- rspec/core_ext")
    allow(load_error).to receive(:path).and_return("rspec/core_ext")
    allow(integration).to receive(:require).and_raise(load_error)
    expect { integration.setup }.to raise_error(LoadError, /rspec\/core_ext/)
  end
end
