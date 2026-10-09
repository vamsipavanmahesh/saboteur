# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::Boot do
  describe ".refuse_recursion!" do
    it "refuses to start inside a saboteur child" do
      stub_const("ENV", ENV.to_h.merge(Saboteur::Execution::Supervisor::CHILD_ENV => "1"))
      expect { described_class.refuse_recursion! }.to raise_error(Saboteur::Error, /refusing to start/)
    end

    it "lets a top-level run start" do
      stub_const("ENV", ENV.to_h.except(Saboteur::Execution::Supervisor::CHILD_ENV))
      expect { described_class.refuse_recursion! }.not_to raise_error
    end
  end

  describe ".watch_for_simplecov" do
    # saboteur needs Ruby's Coverage itself; an app that starts SimpleCov
    # unconditionally (as human-essentials does from config/environments)
    # would otherwise fail to boot under saboteur. saboteur does not load
    # SimpleCov itself: loading it runs the app's .simplecov at once.
    def fake_simplecov
      Module.new do
        def self.start(*) = :started
      end
    end

    it "turns SimpleCov.start into a no-op as soon as the app defines SimpleCov" do
      hide_const("SimpleCov")
      described_class.watch_for_simplecov
      expect { Object.const_set(:SimpleCov, fake_simplecov) }.to output(/SimpleCov\.start ignored/).to_stderr
      expect(SimpleCov.start("rails")).to be_nil
    ensure
      Object.send(:remove_const, :SimpleCov) if Object.const_defined?(:SimpleCov, false)
    end

    # The watcher stays installed once an example installs it, so defining
    # the constant may already be enough; either way it ends up silenced.
    it "turns off a SimpleCov that is already loaded" do
      expect do
        stub_const("SimpleCov", fake_simplecov)
        described_class.watch_for_simplecov
      end.to output(/SimpleCov\.start ignored/).to_stderr
      expect(SimpleCov.start).to be_nil
    end

    it "says nothing while the app has no SimpleCov" do
      hide_const("SimpleCov")
      expect { described_class.watch_for_simplecov }.not_to output.to_stderr
    end
  end

  # If the guard were missing, this spec must fail without starting a run:
  # everything after the guard raises a sentinel instead of doing work.
  it "is the first thing a run does" do
    stub_const("ENV", ENV.to_h.merge(Saboteur::Execution::Supervisor::CHILD_ENV => "1"))
    allow(Saboteur::IgnoreList).to receive(:load).and_raise("guard missing: run went on")
    allow(described_class).to receive(:new).and_raise("guard missing: run went on")
    expect { Saboteur::Engine.new(Saboteur::Config.new({}, root: Dir.pwd)).call }
      .to raise_error(Saboteur::Error, /refusing to start/)
  end
end
