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
      expect { integration.setup }.to raise_error(Saboteur::ConfigError, /rspec is not in the bundle.*test group/m)
    end
  end

  it "refuses configured_spec_files the same way" do
    without_rspec_core do
      expect do
        integration.configured_spec_files(Dir.pwd)
      end.to raise_error(Saboteur::ConfigError, /rspec is not in the bundle/)
    end
  end

  it "re-raises a LoadError for any other file, keeping the crash route" do
    load_error = LoadError.new("cannot load such file -- the_app/boot")
    allow(load_error).to receive(:path).and_return("the_app/boot")
    allow(integration).to receive(:require).and_raise(load_error)
    expect { integration.setup }.to raise_error(LoadError, %r{the_app/boot})
  end

  it "names docs/minitest.md instead of the dead-end c.integration remedy (#610)" do
    without_rspec_core do
      expect { integration.setup }.to raise_error(
        Saboteur::ConfigError,
        %r{saboteur's built-in integration supports RSpec only - see docs/minitest\.md for other suites}
      )
    end
  end

  it "does not offer the dead-end c.integration remedy (#610)" do
    without_rspec_core do
      expect { integration.setup }.to raise_error(Saboteur::ConfigError) { |error|
        expect(error.message).not_to include("point c.integration")
      }
    end
  end

  it "re-raises a LoadError for rspec/core_ext: the message matches, the feature does not" do
    load_error = LoadError.new("cannot load such file -- rspec/core_ext")
    allow(load_error).to receive(:path).and_return("rspec/core_ext")
    allow(integration).to receive(:require).and_raise(load_error)
    expect { integration.setup }.to raise_error(LoadError, %r{rspec/core_ext})
  end
end

# Each public entry point loads the framework itself, before it touches any
# RSpec constant. Stubbing the other loading paths away leaves a single
# require_framework call that can raise, so removing that call is seen.
RSpec.describe Saboteur::Integration::RSpec, "framework load at each entry point (#542)" do
  let(:integration) { described_class.new(Saboteur::Config.new({}, root: Dir.pwd)) }
  let(:load_error) do
    LoadError.new("cannot load such file -- rspec/core").tap do |error|
      allow(error).to receive(:path).and_return("rspec/core")
    end
  end

  it "requires rspec/core by that exact name" do
    allow(integration).to receive(:require).and_return(true)
    integration.send(:require_framework)
    expect(integration).to have_received(:require).with("rspec/core")
  end

  it "loads the real framework without raising" do
    expect { integration.send(:require_framework) }.not_to raise_error
  end

  it "loads the framework at the top of setup, before any RSpec constant is touched" do
    allow(integration).to receive(:rspec_args).and_return([])
    allow(integration).to receive(:require).and_raise(load_error)
    allow(RSpec::Core::Runner).to receive(:disable_autorun!).and_raise("setup ran past the framework load")
    expect { integration.setup }.to raise_error(Saboteur::ConfigError, /rspec is not in the bundle/)
  end

  it "loads the framework in configured_spec_files before reading any RSpec option" do
    allow(integration).to receive(:rspec_args).and_return([])
    allow(integration).to receive(:require).and_raise(load_error)
    allow(RSpec::Core::ConfigurationOptions).to receive(:new).and_raise("read options past the framework load")
    expect { integration.configured_spec_files(Dir.pwd) }
      .to raise_error(Saboteur::ConfigError, /rspec is not in the bundle/)
  end

  it "loads the framework in rspec_args before parsing" do
    allow(integration).to receive(:require).and_raise(load_error)
    allow(RSpec::Core::ConfigurationOptions).to receive(:new).and_raise("parsed past the framework load")
    expect { integration.rspec_args }.to raise_error(Saboteur::ConfigError, /rspec is not in the bundle/)
  end
end
