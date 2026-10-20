# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "pathname"
begin
  require "sqlite3"
rescue LoadError
  nil
end

# The Rails boot guards and the steps after_boot runs, pinned by message and
# by call: which environment variable decides, what each refusal says, and
# which setup runs once Rails has loaded.
RSpec.describe Saboteur::Frameworks::Rails, "boot guards" do
  let(:hooks) { Saboteur::Hooks.new }
  let(:rails) { described_class.new(Saboteur::Config.new({}), hooks) }

  describe "#before_boot" do
    def boot_with(env)
      stub_const("ENV", env)
      rails.before_boot
    end

    it "refuses to run outside the test environment and says what it saw" do
      expect { boot_with({}) }.to raise_error(
        Saboteur::Error, "rails integration refuses to run unless RAILS_ENV=test (got nil)"
      )
      expect { boot_with({ "RAILS_ENV" => "production" }) }.to raise_error(
        Saboteur::Error, 'rails integration refuses to run unless RAILS_ENV=test (got "production")'
      )
    end

    it "reads RACK_ENV when RAILS_ENV is unset, and prefers RAILS_ENV when both are set" do
      expect { boot_with({ "RACK_ENV" => "test" }) }.not_to raise_error
      expect { boot_with({ "RACK_ENV" => "production" }) }.to raise_error(Saboteur::Error, /got "production"/)
      expect { boot_with({ "RAILS_ENV" => "test", "RACK_ENV" => "production" }) }.not_to raise_error
      expect { boot_with({ "RAILS_ENV" => "production", "RACK_ENV" => "test" }) }.to raise_error(
        Saboteur::Error, /got "production"/
      )
    end
  end

  describe "#after_boot" do
    let(:application) { double("application", eager_load!: nil) }
    let(:env) { double("env", test?: true, to_s: "test") }

    before do
      stub_const("Rails", double("Rails", env:, application:))
      allow(Coverage).to receive_messages(state: :running)
      %i[check_databases disconnect snapshot_memory_databases reconnect].each do |step|
        allow(rails).to receive(step)
      end
    end

    it "says in full what to require when Rails did not load" do
      hide_const("Rails")
      expect { rails.after_boot }.to raise_error(
        Saboteur::Error,
        "rails: true but Rails did not load (add config/environment to require - for an engine, " \
        "its dummy app's environment, such as test/dummy/config/environment.rb; only a dynamically " \
        "created dummy app has no environment file, and there you require the helper that calls " \
        "setup instead, such as DummyApp.setup in spec/rails_helper)"
      )
    end

    it "refuses a Rails environment other than test and names it" do
      allow(env).to receive_messages(test?: false, to_s: "production")
      stub_const("Rails", double("Rails", env:, application:))
      expect { rails.after_boot }.to raise_error(
        Saboteur::Error, "rails integration refuses to run: Rails.env is production"
      )
      expect(rails).not_to have_received(:check_databases)
    end

    it "checks the databases, disconnects and snapshots once, in that order" do
      order = []
      allow(rails).to receive(:check_databases) { order << :check }
      allow(rails).to receive(:disconnect) { order << :disconnect }
      allow(rails).to receive(:snapshot_memory_databases) { order << :snapshot }
      allow(application).to receive(:eager_load!) { order << :eager }
      rails.after_boot
      expect(order).to eq(%i[check eager disconnect snapshot])
    end

    it "registers a before_fork hook that disconnects and an after_fork hook that reconnects" do
      rails.after_boot
      expect(rails).to have_received(:disconnect).once
      hooks.run(:before_fork, :mutation)
      expect(rails).to have_received(:disconnect).twice
      expect(rails).not_to have_received(:reconnect)
      hooks.run(:after_fork)
      expect(rails).to have_received(:reconnect).once
    end
  end
end
