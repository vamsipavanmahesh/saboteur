# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

RSpec.describe Saboteur::Engine::Boot do
  describe ".refuse_recursion!" do
    it "refuses to start inside a saboteur child" do
      stub_const("ENV", ENV.to_h.merge(Saboteur::Execution::Supervisor::CHILD_ENV => "1"))
      expect { described_class.refuse_recursion! }.to raise_error(Saboteur::Error, /refusing to start/)
    end

    it "lets a top-level run start" do
      stub_const("ENV", ENV.to_h.except(Saboteur::Execution::Supervisor::CHILD_ENV,
                                        Saboteur::Execution::ExternalRunner::CHILD_MARKER))
      expect { described_class.refuse_recursion! }.not_to raise_error
    end

    # A --test-command command that itself invokes saboteur must not start
    # ANY nested run, with or without its own --test-command (#305 QA).
    it "refuses any run inside an external test command" do
      stub_const("ENV", ENV.to_h.merge(Saboteur::Execution::ExternalRunner::CHILD_MARKER => "1"))
      marker = Saboteur::Execution::ExternalRunner::CHILD_MARKER
      expect { described_class.refuse_recursion! }.to raise_error(
        Saboteur::Error,
        "refusing to start: this process runs inside a saboteur external test command " \
        "(#{marker} is set); a nested run could race its tree"
      )
    end

    it "names the child marker in the in-process refusal (#305 dogfood)" do
      stub_const("ENV", ENV.to_h.merge(Saboteur::Execution::Supervisor::CHILD_ENV => "1"))
      child_env = Saboteur::Execution::Supervisor::CHILD_ENV
      expect { described_class.refuse_recursion! }.to raise_error(
        Saboteur::Error,
        "refusing to start: this process is a saboteur child " \
        "(#{child_env} is set). A test is running saboteur itself; stub it."
      )
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

    it "clears the current hooks after loading, also when a hooks file raises" do
      Dir.mktmpdir do |dir|
        root = File.realpath(dir)
        File.write(File.join(root, "ok.rb"),
                   "File.write(File.join(__dir__, 'seen'), Saboteur.current_hooks.object_id)\n")
        File.write(File.join(root, "bad.rb"), "raise 'boom'\n")
        hooks = Saboteur::Hooks.new
        described_class.new(Saboteur::Config.new({ "hooks" => ["./ok.rb"] }, root: root), hooks).send(:load_hooks)
        expect(File.read(File.join(root, "seen"))).to eq(hooks.object_id.to_s)
        expect(Saboteur.current_hooks).to be_nil
        failing = described_class.new(Saboteur::Config.new({ "hooks" => ["./bad.rb"] }, root: root), hooks)
        expect { failing.send(:load_hooks) }.to raise_error("boom")
        expect(Saboteur.current_hooks).to be_nil
      end
    end

    it "loads the exact extensionless file when both it and its .rb exist" do
      Dir.mktmpdir do |dir|
        root = File.realpath(dir)
        FileUtils.mkdir_p(File.join(root, "config"))
        File.write(File.join(root, "config", "saboteur_hooks"),
                   "File.write(File.join(File.dirname(__FILE__), 'loaded-bare'), 'yes')\n")
        File.write(File.join(root, "config", "saboteur_hooks.rb"),
                   "File.write(File.join(File.dirname(__FILE__), 'loaded-rb'), 'yes')\n")
        config = Saboteur::Config.new({ "hooks" => ["./config/saboteur_hooks"] }, root: root)
        described_class.new(config, Saboteur::Hooks.new).send(:load_hooks)
        expect(File.exist?(File.join(root, "config", "loaded-bare"))).to be(true)
        expect(File.exist?(File.join(root, "config", "loaded-rb"))).to be(false)
      end
    end

    it "loads a dotted path itself even when a path.rb.rb exists beside it" do
      Dir.mktmpdir do |dir|
        root = File.realpath(dir)
        FileUtils.mkdir_p(File.join(root, "config"))
        File.write(File.join(root, "config", "saboteur_hooks.rb"),
                   "File.write(File.join(File.dirname(__FILE__), 'loaded-rb'), 'yes')\n")
        File.write(File.join(root, "config", "saboteur_hooks.rb.rb"),
                   "File.write(File.join(File.dirname(__FILE__), 'loaded-rb-rb'), 'yes')\n")
        config = Saboteur::Config.new({ "hooks" => ["./config/saboteur_hooks.rb"] }, root: root)
        described_class.new(config, Saboteur::Hooks.new).send(:load_hooks)
        expect(File.exist?(File.join(root, "config", "loaded-rb"))).to be(true)
        expect(File.exist?(File.join(root, "config", "loaded-rb-rb"))).to be(false)
      end
    end

    it "fails loudly on a dotted path that does not exist, even when a path.rb.rb does" do
      Dir.mktmpdir do |dir|
        root = File.realpath(dir)
        FileUtils.mkdir_p(File.join(root, "config"))
        File.write(File.join(root, "config", "saboteur_hooks.rb.rb"), "# not a hook\n")
        config = Saboteur::Config.new({ "hooks" => ["./config/saboteur_hooks.rb"] }, root: root)
        expect { described_class.new(config, Saboteur::Hooks.new).send(:load_hooks) }
          .to raise_error(LoadError) { |error| expect(error.message).to include("saboteur_hooks.rb") }
      end
    end

    it "still fails loudly when neither the path nor its .rb exists" do
      Dir.mktmpdir do |dir|
        root = File.realpath(dir)
        config = Saboteur::Config.new({ "hooks" => ["./config/saboteur_hooks"] }, root: root)
        expect { described_class.new(config, Saboteur::Hooks.new).send(:load_hooks) }
          .to raise_error(LoadError) { |error|
            expect(error.message).to include("saboteur_hooks")
            expect(error.message).not_to include("saboteur_hooks.rb")
          }
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

    it "warns before the spec load when the environment looks wrong (#598, #609)" do
      Dir.mktmpdir do |dir|
        config = Saboteur::Config.new({ "require" => [] }, root: dir)
        allow(Saboteur::EnvironmentHints).to receive(:all).and_return(["a fake hint"])
        expect { boot_with(config, dir) }.to output(/saboteur: warning: a fake hint/).to_stderr
      end
    end

    it "loads RSpec core before a non-Rails helper without requiring it itself (#616)" do
      Dir.mktmpdir do |dir|
        helper = File.join(dir, "helper.rb")
        File.write(helper, "RSpec.configure { |c| c.add_setting :boot_helper_loaded, default: true }\n")
        script = <<~RUBY
          require "saboteur"
          require "saboteur/engine"
          abort "RSpec was loaded before boot" if defined?(::RSpec)
          class Saboteur::Integration::RSpec
            def setup; end
          end
          config = Saboteur::Config.new({ "require" => [#{helper.dump}] }, root: #{dir.dump})
          Saboteur::Engine::Boot.new(config, Saboteur::Hooks.new).load_target
          abort "helper did not run" unless RSpec.configuration.boot_helper_loaded
        RUBY
        out, err, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../../../lib", __dir__), "-e", script)
        expect(status.success?).to be(true), "#{out}#{err}"
      end
    end

    it "requires the framework before loading configured files in this process (#616)" do
      Dir.mktmpdir do |dir|
        helper = File.join(dir, "helper.rb")
        File.write(helper, "# boot helper\n")
        config = Saboteur::Config.new({ "require" => [helper] }, root: dir)
        integration = instance_double(Saboteur::Integration::RSpec, setup: nil)
        allow(Saboteur::Integration::RSpec).to receive(:new).with(config).and_return(integration)
        expect(integration).to receive(:require_framework).ordered
        expect(integration).to receive(:setup).ordered
        begin
          described_class.new(config, Saboteur::Hooks.new).load_target
        ensure
          $LOAD_PATH.delete(File.join(File.realpath(dir), "spec"))
        end
      end
    end

    it "does not require RSpec for another integration (#616)" do
      Dir.mktmpdir do |dir|
        config = Saboteur::Config.new({ "integration" => "custom" }, root: dir)
        expect(Saboteur::Integration::RSpec).not_to receive(:new)
        begin
          boot_with(config, dir)
        ensure
          $LOAD_PATH.delete(File.join(File.realpath(dir), "spec"))
        end
      end
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

    # Non-Rails gems do not add spec/ to the load path themselves, so the
    # boot load of their spec helper fails without this (#615).
    it "puts spec/ on the load path when rails: false (non-Rails gem)" do
      Dir.mktmpdir do |dir|
        spec_dir = File.join(dir, "spec")
        Dir.mkdir(spec_dir)
        File.write(File.join(spec_dir, "dummy_env.rb"), "DUMMY_ENV_LOADED = true\n")
        File.write(File.join(spec_dir, "spec_helper.rb"), 'require "dummy_env"')
        config = Saboteur::Config.new({ "require" => ["./spec/spec_helper"] }, root: dir)
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
  end

  it "hands the run's palette to diagnostics" do
    err = StringIO.new
    palette = Saboteur::Reporter::Palette.new(enabled: false)
    allow(Saboteur::Engine::Diagnostics).to receive(:new).and_call_original
    Saboteur::Engine.new(Saboteur::Config.new({}, root: Dir.pwd), err: err, palette: palette)
    expect(Saboteur::Engine::Diagnostics).to have_received(:new).with(err, verbose: false, palette: palette,
                                                                           quiet_start: true)
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
