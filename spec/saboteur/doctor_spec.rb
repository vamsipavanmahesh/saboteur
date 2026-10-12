# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "saboteur/doctor"

RSpec.describe Saboteur::Doctor do
  let(:config) { Saboteur::Config.new }
  let(:out) { StringIO.new }
  let(:doctor) { described_class.new(config, out: out) }

  before do
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Coverage).to receive(:supported?).with(:lines).and_return(true)
    allow(Coverage).to receive(:supported?).with(:methods).and_return(true)
  end

  it "boots once, checks coverage before and after boot, and reports two baseline runs" do
    hide_const("SimpleCov")
    integration = instance_double(Saboteur::Integration::Base)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration)
    expect(Saboteur::Engine::Boot).to receive(:new).with(config, instance_of(Saboteur::Hooks)).and_return(boot)
    expect(Coverage).to receive(:state).twice.and_return(:suspended)
    expect(Saboteur::BaselineHealth).to receive(:new).with(config, integration: integration, hooks: instance_of(Saboteur::Hooks))
                                                     .and_return(instance_double(Saboteur::BaselineHealth,
                                                                                 call: %w[a b]))
    expect(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    expect(doctor).to receive(:check_boot_files).and_call_original
    expect(doctor.call).to be(true)
    expect(out.string).to include("Ruby:", "Coverage: suspended", "Integration: rspec (loaded)", "Rails: disabled",
                                  "Baseline: 2 tests passed twice in the same order with seed 1", "does not prove",
                                  "SimpleCov: not loaded", "Custom map: none (optional)")
  end

  it "reports the loaded map and warns about duplicate keys" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "app", "models"))
      File.write(File.join(root, "app", "models", "dup.rb"), "# app\n")
      File.write(File.join(root, "app", "models", "dup_b.rb"), "# app\n")
      FileUtils.mkdir_p(File.join(root, "spec", "models"))
      File.write(File.join(root, "spec", "models", "dup_spec.rb"), "# spec\n")
      File.write(File.join(root, "spec", "models", "dup_b_spec.rb"), "# spec\n")
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config", "saboteur_custom_map.rb"), <<~RUBY)
        SABOTEUR_CUSTOM_MAP = {
          "app/models/dup.rb" => ["spec/models/dup_spec.rb"],
          "app/models/dup.rb" => ["spec/models/dup_b_spec.rb"],
          "app/models/dup_b.rb" => ["spec/models/dup_b_spec.rb"],
          "app/models/dup_b.rb" => ["spec/models/dup_spec.rb"],
        }.freeze
      RUBY
      config = Saboteur::Config.new({}, root: File.realpath(root))
      doctor = described_class.new(config, out: out)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(instance_double(Saboteur::Engine::Boot,
                                                                                load_target: nil))
      allow(Saboteur::BaselineHealth).to receive(:new).and_return(instance_double(Saboteur::BaselineHealth,
                                                                                  call: ["a"]))
      doctor.call
      expect(out.string).to include(
        "Warning: custom map keys written twice, Ruby keeps the last: app/models/dup.rb, app/models/dup_b.rb",
        "Custom map: 2 entries (loaded)"
      )
    end
  end

  it "fails on stale map keys and names them" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "spec", "models"))
      File.write(File.join(root, "spec", "models", "gone_spec.rb"), "# spec\n")
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config", "saboteur_custom_map.rb"),
                 "SABOTEUR_CUSTOM_MAP = { \"app/models/gone.rb\" => [\"spec/models/gone_spec.rb\"], " \
                 "\"app/models/gone_b.rb\" => [\"spec/models/gone_spec.rb\"] }.freeze\n")
      config = Saboteur::Config.new({}, root: File.realpath(root))
      doctor = described_class.new(config, out: out)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(instance_double(Saboteur::Engine::Boot,
                                                                                load_target: nil))
      allow(Saboteur::BaselineHealth).to receive(:new).and_return(instance_double(Saboteur::BaselineHealth,
                                                                                  call: ["a"]))
      expect { doctor.call }.to raise_error(Saboteur::ConfigError) { |error|
        expect(error.message).to include("stale keys matching no file: app/models/gone.rb, app/models/gone_b.rb")
      }
    end
  end

  it "loads a clean map without warnings" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "app", "models"))
      File.write(File.join(root, "app", "models", "user.rb"), "# app\n")
      FileUtils.mkdir_p(File.join(root, "spec", "models"))
      File.write(File.join(root, "spec", "models", "user_spec.rb"), "# spec\n")
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config", "saboteur_custom_map.rb"),
                 "SABOTEUR_CUSTOM_MAP = { \"app/models/user.rb\" => [\"spec/models/user_spec.rb\"] }.freeze\n")
      config = Saboteur::Config.new({}, root: File.realpath(root))
      doctor = described_class.new(config, out: out)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(instance_double(Saboteur::Engine::Boot,
                                                                                load_target: nil))
      allow(Saboteur::BaselineHealth).to receive(:new).and_return(instance_double(Saboteur::BaselineHealth,
                                                                                  call: ["a"]))
      doctor.call
      expect(out.string).to include("Custom map: 1 entries (loaded)")
      expect(out.string).not_to include("written twice")
    end
  end

  it "does not mark valid ignore subjects unmatched because of a subject filter" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib", "probe.rb"), "class Probe; def valid; true; end; end")
      config = Saboteur::Config.new({ "subjects" => ["Other"] }, root: root)
      ignores = Saboteur::IgnoreList.new([Saboteur::IgnoreList::Entry.new(subject: "Probe#valid",
                                                                          mutation: "a", reason: "accepted")])
      allow(Saboteur::IgnoreList).to receive(:load).with(config.path("ignore_file")).and_return(ignores)

      described_class.new(config, out: out).send(:check_ignore_subjects)

      expect(out.string).to be_empty
    end
  end

  it "reports an incomplete ignore check instead of unmatched subjects when source parsing fails" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib", "probe.rb"), "class Probe; def valid;")
      config = Saboteur::Config.new({}, root: root)
      ignores = Saboteur::IgnoreList.new([Saboteur::IgnoreList::Entry.new(subject: "Probe#valid",
                                                                          mutation: "a", reason: "accepted")])
      allow(Saboteur::IgnoreList).to receive(:load).with(config.path("ignore_file")).and_return(ignores)

      described_class.new(config, out: out).send(:check_ignore_subjects)

      expect(out.string).to include("ignore subject check incomplete")
      expect(out.string).not_to include("matches no discovered subject")
    end
  end

  it "drives the full call and reports a duplicated unmatched subject once with exact guidance" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config", "saboteur_ignore.rb"), <<~RUBY)
        Saboteur.ignore do |i|
          i.mutation "a", subject: "Gone#method", reason: "accepted"
          i.mutation "b", subject: "Gone#method", reason: "accepted"
        end
      RUBY
      config = Saboteur::Config.new({}, root: root)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(instance_double(Saboteur::Engine::Boot,
                                                                                load_target: nil))
      allow(Saboteur::BaselineHealth).to receive(:new).and_return(instance_double(Saboteur::BaselineHealth,
                                                                                  call: ["a"]))

      expect(described_class.new(config, out: out).call).to be(true)

      warnings = out.string.lines.grep(/Warning: ignore subject/)
      expect(warnings).to eq(["Warning: ignore subject Gone#method matches no discovered subject in included files; " \
                              "check include/exclude settings and the exact Class#method or Class.method form\n"])
    end
  end

  it "does not parse sources or print ignore warnings when the ignore list is empty" do
    allow(Saboteur::IgnoreList).to receive(:load).and_return(Saboteur::IgnoreList.new([]))
    expect(Saboteur::SubjectFinder).not_to receive(:new)
    expect(config).not_to receive(:included_files)

    doctor.send(:check_ignore_subjects)

    expect(out.string).to be_empty
  end

  it "reports a malformed ignore file as a config error before target boot" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "config"))
      path = File.join(root, "config", "saboteur_ignore.rb")
      File.write(path, 'Saboteur.ignore { |i| i.mutation "a", subject: "Gone#method" }')
      config = Saboteur::Config.new({}, root: root)
      expect(Saboteur::Engine::Boot).not_to receive(:new)

      expect { described_class.new(config, out: out).call }.to raise_error(Saboteur::ConfigError, /missing reason/)
      expect(File.read(path)).to include('subject: "Gone#method"')
    end
  end

  it "reports enabled Rails and present SimpleCov" do
    stub_const("SimpleCov", Module.new)
    allow(config).to receive(:[]).and_call_original
    allow(config).to receive(:[]).with("rails").and_return(true)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(instance_double(Saboteur::Engine::Boot, load_target: nil))
    allow(Saboteur::BaselineHealth).to receive(:new).and_return(instance_double(Saboteur::BaselineHealth, call: ["a"]))
    doctor.call
    expect(out.string).to include("Rails: enabled", "SimpleCov: present; start suppressed for this process")
  end

  it "rejects unsupported Ruby, no fork, and non-RSpec adapters" do
    stub_const("RUBY_VERSION", "3.2.9")
    expect { doctor.send(:check_runtime) }.to raise_error(Saboteur::Error, /Ruby 3.3/)
    stub_const("RUBY_VERSION", "3.3.0")
    allow(Process).to receive(:respond_to?).with(:fork).and_return(false)
    expect { doctor.send(:check_runtime) }.to raise_error(Saboteur::Error, /with fork/)
    allow(Process).to receive(:respond_to?).with(:fork).and_return(true)
    allow(config).to receive(:[]).with("integration").and_return("other")
    expect { doctor.send(:check_runtime) }.to raise_error(Saboteur::ConfigError, /rspec/)
  end

  it "requires both suspended coverage and line support" do
    allow(Coverage).to receive(:state).and_return(:running)
    expect { doctor.send(:check_coverage) }.to raise_error(Saboteur::Error, /Coverage must be suspended/)
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Coverage).to receive(:supported?).and_return(false)
    expect { doctor.send(:check_coverage) }.to raise_error(Saboteur::Error, /line and method support/)
  end

  it "requires method coverage support too, for endless defs (issue #107)" do
    allow(Coverage).to receive(:supported?).with(:methods).and_return(false)
    expect { doctor.send(:check_coverage) }.to raise_error(Saboteur::Error, /line and method support/)
  end

  it "checks both require and hook files and warns about unmatched include patterns" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "boot.rb"), "")
      config = Saboteur::Config.new(
        { "require" => ["boot.rb"], "hooks" => ["missing.rb"], "include" => ["none/*.rb"] }, root: root
      )
      doctor = described_class.new(config, out: out)
      expect { doctor.send(:check_boot_files) }.to raise_error(Saboteur::ConfigError, /hooks file missing: missing.rb/)
      File.write(File.join(root, "missing.rb"), "")
      doctor.send(:check_boot_files)
      expect(out.string).to include("require: boot.rb (found)", "hooks: missing.rb (found)",
                                    "none/*.rb matches no file")
      File.unlink(File.join(root, "boot.rb"))
      expect { doctor.send(:check_boot_files) }.to raise_error(Saboteur::ConfigError, /require file missing/)
    end
  end

  it "wraps load, syntax, exit, and ordinary boot failures without swallowing interrupts" do
    boot = instance_double(Saboteur::Engine::Boot)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    [LoadError, SyntaxError, SystemExit, RuntimeError].each do |type|
      allow(boot).to receive(:load_target).and_raise(type.new("broken"))
      expect do
        doctor.send(:boot_target, Saboteur::Hooks.new)
      end.to raise_error(Saboteur::Error, /target boot failed: #{type}/)
    end
    allow(boot).to receive(:load_target).and_raise(Interrupt)
    expect { doctor.send(:boot_target, Saboteur::Hooks.new) }.to raise_error(Interrupt)
  end
end

RSpec.describe Saboteur::CLI, "doctor command" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  it "parses config and seed and calls doctor, not the mutation engine" do
    config = Saboteur::Config.new
    expect(Saboteur::Config).to receive(:load).with(root: Dir.pwd, path: "health.yml",
                                                    overrides: { seed: 42 }).and_return(config)
    expect(Saboteur::Doctor).to receive(:new).with(config,
                                                   out: out).and_return(instance_double(Saboteur::Doctor, call: true))
    expect(Saboteur::Engine).not_to receive(:new)
    expect(described_class.new(%w[doctor --config health.yml --seed 42], out: out, err: err).call).to eq(0)
  end

  it "describes doctor options in its own parser banner" do
    command = described_class.new(["doctor"], out: out, err: err)
    expect(command.send(:doctor_parser).to_s).to include("Usage: saboteur doctor [--config PATH] [--seed N]")
  end

  it "returns usage for stray or invalid arguments, and reports config and tool failures" do
    expect(described_class.new(%w[doctor extra], out: out, err: err).call).to eq(2)
    expect(err.string).to include("unexpected arguments: extra")
    expect(described_class.new(%w[doctor --seed bad], out: out, err: err).call).to eq(2)
    [Saboteur::ConfigError, Saboteur::Error].zip([2, 3]).each do |type, code|
      err.truncate(0)
      err.rewind
      allow(Saboteur::Doctor).to receive(:new).and_raise(type, "health problem")
      expect(described_class.new(["doctor"], out: out, err: err).call).to eq(code)
      expect(err.string).to include("saboteur: health problem")
    end
  end
end
