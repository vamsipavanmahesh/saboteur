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

  describe "#load_hooks" do
    it "loads an extensionless hooks path through its .rb file, the way require resolves it" do
      Dir.mktmpdir do |dir|
        root = File.realpath(dir)
        FileUtils.mkdir_p(File.join(root, "config"))
        File.write(File.join(root, "config", "saboteur_hooks.rb"),
                   "File.write(File.join(File.dirname(__FILE__), 'loaded'), 'yes')\n")
        config = Saboteur::Config.new({ "hooks" => ["./config/saboteur_hooks"] }, root: root)
        described_class.new(config, Saboteur::Hooks.new).send(:load_hooks)
        expect(File.exist?(File.join(root, "config", "loaded"))).to be(true)
      end
    end

    it "still fails loudly when neither the path nor its .rb exists" do
      Dir.mktmpdir do |dir|
        root = File.realpath(dir)
        config = Saboteur::Config.new({ "hooks" => ["./config/saboteur_hooks"] }, root: root)
        expect { described_class.new(config, Saboteur::Hooks.new).send(:load_hooks) }.to raise_error(LoadError)
      end
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

  describe "#load_target" do
    def boot_with(config, _dir)
      rails = instance_double(Saboteur::Frameworks::Rails, before_boot: nil, after_boot: nil)
      allow(Saboteur::Frameworks::Rails).to receive(:new).and_return(rails)
      integration = instance_double(Saboteur::Integration::RSpec, setup: nil)
      allow(Saboteur::Integration).to receive(:fetch).and_return(double(new: integration))
      described_class.new(config, Saboteur::Hooks.new).load_target
    end

    # rspec puts spec/ on the load path, so a boot file under spec/ (a
    # dummy app's rails_helper, say) can require its siblings. saboteur
    # must match that, or the same require list fails to load.
    it "puts spec/ on the load path when rails: true, so boot files can require siblings" do
      Dir.mktmpdir do |dir|
        spec_dir = File.join(dir, "spec")
        Dir.mkdir(spec_dir)
        File.write(File.join(spec_dir, "dummy_env.rb"), "DUMMY_ENV_LOADED = true\n")
        File.write(File.join(spec_dir, "rails_helper.rb"), 'require "dummy_env"')
        config = Saboteur::Config.new({ "rails" => true, "require" => ["./spec/rails_helper"] }, root: dir)
        begin
          boot_with(config, dir)
          expect(defined?(DUMMY_ENV_LOADED)).to eq("constant")
          expect($LOAD_PATH).to include(File.realpath(spec_dir))
        ensure
          Object.send(:remove_const, :DUMMY_ENV_LOADED) if defined?(DUMMY_ENV_LOADED)
          $LOAD_PATH.delete(File.realpath(spec_dir))
          $LOADED_FEATURES.delete_if { |feature| feature.start_with?(File.realpath(dir)) }
        end
      end
    end

    it "does not add spec/ twice when it is already on the load path" do
      Dir.mktmpdir do |dir|
        path = File.join(File.realpath(dir), "spec")
        $LOAD_PATH.unshift(path)
        config = Saboteur::Config.new({ "rails" => true, "require" => [] }, root: dir)
        begin
          boot_with(config, dir)
          expect($LOAD_PATH.count(path)).to eq(1)
        ensure
          $LOAD_PATH.delete(path)
        end
      end
    end

    it "leaves the load path alone when rails: false" do
      Dir.mktmpdir do |dir|
        config = Saboteur::Config.new({ "require" => [] }, root: dir)
        expect { boot_with(config, dir) }.not_to(change { $LOAD_PATH.dup })
      end
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
