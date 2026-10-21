# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "saboteur/doctor"

RSpec.describe Saboteur::Doctor do
  let(:config) { Saboteur::Config.new }
  let(:out) { StringIO.new }
  let(:suite) { true }
  let(:doctor) { described_class.new(config, out: out, suite: suite) }

  before do
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Coverage).to receive(:supported?).with(:lines).and_return(true)
    allow(Coverage).to receive(:supported?).with(:methods).and_return(true)
  end

  it "names bundler and appraisal problems on the Environment line (#598, #609)" do
    doctor = described_class.new(config, out: out)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Appraisals"), "appraise \"a\" do\nend\n")
      allow(config).to receive(:root).and_return(dir)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("BUNDLE_GEMFILE").and_return(nil)
      doctor.send(:check_environment)
    end
    expect(out.string).to include("Environment: Appraisal gemfiles found (Appraisals) but BUNDLE_GEMFILE is not set:")
  end

  it "joins several hints with a separator" do
    doctor = described_class.new(config, out: out)
    allow(Saboteur::EnvironmentHints).to receive(:all).and_return(["hint one", "hint two"])
    doctor.send(:check_environment)
    expect(out.string).to include("Environment: hint one; hint two")
  end

  it "reports a clean Environment line when nothing is detected" do
    doctor = described_class.new(config, out: out)
    Dir.mktmpdir do |dir|
      allow(config).to receive(:root).and_return(dir)
      doctor.send(:check_environment)
    end
    expect(out.string).to include("Environment: no bundler/appraisal problems detected")
  end

  it "boots once, checks coverage before and after boot, and reports two baseline runs" do
    hide_const("SimpleCov")
    # The repo's own dogfood map must not move this pin (#1077): doctor reports
    # whatever custom map the project has, so the check sees none here.
    allow(Saboteur::CustomMap).to receive(:load).and_return(Saboteur::CustomMap.new([]))
    integration = instance_double(Saboteur::Integration::Base)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration)
    expect(Saboteur::Engine::Boot).to receive(:new).with(config, instance_of(Saboteur::Hooks)).and_return(boot)
    expect(Coverage).to receive(:state).twice.and_return(:suspended)
    expect(Saboteur::BaselineHealth).to receive(:new).with(config, integration: integration, hooks: instance_of(Saboteur::Hooks))
                                                     .and_return(instance_double(Saboteur::BaselineHealth,
                                                                                 call: %w[a b]))
    expect(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    expect(doctor).to receive(:check_boot_files).and_call_original
    expect(doctor).to receive(:check_database_hosts).and_call_original
    expect(doctor.call).to be(true)
    expect(out.string).to include("Ruby:", "Coverage: suspended", "Integration: rspec (loaded)", "Rails: disabled",
                                  "Baseline: 2 tests passed twice in the same order with seed 1", "does not prove",
                                  "SimpleCov: not loaded", "Custom map: none (optional)",
                                  "Environment: no bundler/appraisal problems detected")
  end

  it "prints the coverage line once while verifying it before and after boot" do
    hide_const("SimpleCov")
    allow(Saboteur::Engine::Boot).to receive(:new)
      .and_return(instance_double(Saboteur::Engine::Boot, load_target: instance_double(Saboteur::Integration::Base)))
    allow(Saboteur::BaselineHealth).to receive(:new)
      .and_return(instance_double(Saboteur::BaselineHealth, call: %w[a]))
    doctor.call
    expect(out.string.scan("Coverage:").size).to eq(1)
  end

  context "sandbox status" do
    let(:suite) { false }

    before do
      hide_const("SimpleCov")
      allow(Saboteur::Engine::Boot).to receive(:new)
        .and_return(instance_double(Saboteur::Engine::Boot, load_target: instance_double(Saboteur::Integration::Base)))
    end

    it "reports the kernel capability, not verified isolation, when the sandbox can deliver" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(4)
      doctor.call
      expect(out.string).to include("Sandbox: kernel Landlock ABI 4 - capability probe only, not verified isolation")
    end

    it "reports the gap as what children would run with when the kernel cannot deliver ABI 3" do
      # Pin the Linux wording as Linux: #667 makes sandbox_gap platform-aware,
      # so an unstubbed darwin? would print "macOS has no Landlock" here.
      allow(Saboteur::Execution::Seatbelt).to receive(:darwin?).and_return(false)
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
      doctor.call
      expect(out.string).to include("Sandbox: this kernel lacks Landlock (needs Linux 6.2+)",
                                    "children would run with the hazard guard and canary only")
    end

    it "says plainly on macOS that mutants run unsandboxed and advises a container" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
      stub_const("RUBY_PLATFORM", "arm64-darwin23")
      doctor.call
      sandbox_note = "macOS: mutants run unsandboxed (Landlock is Linux-only) - a container contains " \
                     "filesystem writes outside the project"
      network_note = "Network: never restricted on any platform, and a plain container keeps outbound " \
                     "access - deny or stub the network when a mutant could reach real APIs"
      seatbelt_note = 'macOS: opt into the sandbox with c.sandbox = "seatbelt" ' \
                      "(docs/guides/macos-seatbelt-sandbox.md), or set c.sandbox = false to silence this"
      expect(out.string).to include(sandbox_note, network_note, seatbelt_note)
    end

    it "reports the Seatbelt probe on macOS when the opt-in is configured (#436)" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
      stub_const("RUBY_PLATFORM", "arm64-darwin23")
      allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:ok)
      configured = Saboteur::Config.new({ "sandbox" => "seatbelt" })
      described_class.new(configured, out: out).call
      expect(out.string).to include(
        "Seatbelt (opt-in, #436): probe ok - capability probe only, not verified isolation"
      )
    end

    it "keeps the Seatbelt probe note off Linux even with the opt-in configured" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
      stub_const("RUBY_PLATFORM", "x86_64-linux")
      configured = Saboteur::Config.new({ "sandbox" => "seatbelt" })
      described_class.new(configured, out: out).call
      expect(out.string).not_to include("Seatbelt (opt-in, #436)")
    end

    it "keeps the macOS note off other platforms" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
      stub_const("RUBY_PLATFORM", "x86_64-linux")
      doctor.call
      expect(out.string).not_to include("mutants run unsandboxed (Landlock is Linux-only)")
    end

    # The Seatbelt line is for the opt-in value on macOS only: it names
    # the probe verdict as a capability probe, not verified isolation.
    it "reports the Seatbelt probe verdict on macOS when c.sandbox = \"seatbelt\"" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
      allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:unsupported_platform)
      stub_const("RUBY_PLATFORM", "arm64-darwin23")
      configured = Saboteur::Config.new({ "sandbox" => "seatbelt" })
      described_class.new(configured, out: out).call
      expect(out.string).to include("Seatbelt (opt-in, #436): probe unsupported_platform - capability probe only, " \
                                    "not verified isolation")
    end

    it "keeps the Seatbelt line off other platforms even with the opt-in value" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(0)
      stub_const("RUBY_PLATFORM", "x86_64-linux")
      configured = Saboteur::Config.new({ "sandbox" => "seatbelt" })
      described_class.new(configured, out: out).call
      expect(out.string).not_to include("Seatbelt (opt-in")
    end

    it "reports the sandbox as off when configured off" do
      configured = Saboteur::Config.new({ "sandbox" => false })
      described_class.new(configured, out: out).call
      expect(out.string).to include("Sandbox: off")
    end

    it "prints no further sandbox verdict when configured off" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(4)
      configured = Saboteur::Config.new({ "sandbox" => false })
      described_class.new(configured, out: out).call
      expect(out.string).not_to include("Landlock ABI")
    end

    it "reports the Landlock ABI at the minimum supported version" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
      doctor.call
      expect(out.string).to include("Sandbox: kernel Landlock ABI 3")
    end

    it "reports the gap one ABI below the minimum" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(2)
      doctor.call
      expect(out.string).to include("Sandbox: this kernel's Landlock ABI is 2 but ABI 3")
    end

    it "distinguishes a strict refusal from permitted degradation" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(2)
      configured = Saboteur::Config.new({ "sandbox" => "strict" })
      described_class.new(configured, out: out).call
      expect(out.string).to include("this kernel's Landlock ABI is 2 but ABI 3",
                                    'c.sandbox = "strict" refuses to run')
      expect(out.string).not_to include("hazard guard")
    end

    it "reports a refused Landlock probe as an actionable tool error, not a crash" do
      allow(Saboteur::Execution::Sandbox).to receive(:abi_version)
        .and_raise(SystemCallError.new("landlock_create_ruleset probe", 1))
      expect { doctor.call }.to raise_error(Saboteur::Error, /Landlock probe failed.*c\.sandbox = false/m)
    end
  end

  context "without --suite" do
    let(:suite) { false }

    it "checks the environment and does not run the suite" do
      hide_const("SimpleCov")
      allow(Saboteur::Engine::Boot).to receive(:new)
        .and_return(instance_double(Saboteur::Engine::Boot, load_target: instance_double(Saboteur::Integration::Base)))
      expect(Saboteur::BaselineHealth).not_to receive(:new)
      expect(doctor.call).to be(true)
      expect(out.string).to include("Ruby:", "Coverage: suspended", "Integration: rspec (loaded)",
                                    "Baseline: not run. Pass --suite to run the unchanged suite twice " \
                                    "(add --test PATH to limit it to some specs).")
      expect(out.string).not_to include("passed twice")
    end
  end

  it "defaults to environment checks only" do
    expect(described_class.new(config, out: out).instance_variable_get(:@suite)).to be(false)
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

  it "requires line support even when method support is present" do
    allow(Coverage).to receive(:supported?).with(:lines).and_return(false)
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
                                    "none/*.rb matches no file - point include at your code in config/saboteur.rb")
      File.unlink(File.join(root, "boot.rb"))
      expect { doctor.send(:check_boot_files) }.to raise_error(Saboteur::ConfigError, /require file missing/)
    end
  end

  it "accepts require and hooks paths that resolve with the .rb extension, the way require does" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config", "environment.rb"), "")
      config = Saboteur::Config.new({ "require" => ["./config/environment"], "hooks" => ["./config/environment"] },
                                    root: root)
      doctor = described_class.new(config, out: out)
      doctor.send(:check_boot_files)
      expect(out.string).to include("require: ./config/environment (found)", "hooks: ./config/environment (found)")
      File.unlink(File.join(root, "config", "environment.rb"))
      expect { doctor.send(:check_boot_files) }.to raise_error(Saboteur::ConfigError, /require file missing/)
    end
  end

  it "prints test database hosts and refuses ones that are neither local nor allowed" do
    primary = double("primary", name: "primary", configuration_hash: { host: "0.0.0.0" })
    animals = double("animals", name: "animals", configuration_hash: { host: "db.internal" })
    cache = double("cache", name: "cache", configuration_hash: { host: "db2.internal" })
    configurations = double("configurations")
    base = double("ActiveRecord::Base")
    allow(base).to receive(:configurations).and_return(configurations)
    expect(configurations).to receive(:configs_for).with(env_name: "test").and_return([primary, animals, cache])
    stub_const("ActiveRecord::Base", base)
    config = Saboteur::Config.new({ "rails" => true })
    doctor = described_class.new(config, out: out)
    expect { doctor.send(:check_database_hosts) }
      .to raise_error(Saboteur::ConfigError,
                      /animals \(host db\.internal\), cache \(host db2\.internal\).*c\.allow_db_hosts/m)
    expect(out.string).to include("Database: primary (host 0.0.0.0)", "Database: animals (host db.internal)",
                                  "Database: cache (host db2.internal)")
  end

  it "accepts a database host the user lists in allow_db_hosts" do
    animals = double("animals", name: "animals", configuration_hash: { host: "db.internal" })
    base = double("ActiveRecord::Base")
    allow(base).to receive(:configurations).and_return(double("configurations", configs_for: [animals]))
    stub_const("ActiveRecord::Base", base)
    config = Saboteur::Config.new({ "rails" => true, "allow_db_hosts" => ["db.internal"] })
    doctor = described_class.new(config, out: out)
    doctor.send(:check_database_hosts)
    expect(out.string).to include("Database: animals (host db.internal)")
  end

  it "skips the database host check unless rails is enabled" do
    doctor = described_class.new(Saboteur::Config.new, out: out)
    doctor.send(:check_database_hosts)
    expect(out.string).to be_empty
  end

  it "says so when rails is enabled but ActiveRecord did not load" do
    hide_const("ActiveRecord")
    config = Saboteur::Config.new({ "rails" => true })
    doctor = described_class.new(config, out: out)
    doctor.send(:check_database_hosts)
    expect(out.string).to include("Databases: ActiveRecord did not load; host check skipped")
  end

  it "prints local socket for a database without a host" do
    primary = double("primary", name: "primary", configuration_hash: { adapter: "sqlite3" })
    base = double("ActiveRecord::Base")
    allow(base).to receive(:configurations).and_return(double("configurations", configs_for: [primary]))
    stub_const("ActiveRecord::Base", base)
    config = Saboteur::Config.new({ "rails" => true })
    doctor = described_class.new(config, out: out)
    doctor.send(:check_database_hosts)
    expect(out.string).to include("Database: primary (host local socket)")
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
                                                   out: out, suite: false)
                                             .and_return(instance_double(Saboteur::Doctor, call: true))
    expect(Saboteur::Engine).not_to receive(:new)
    expect(described_class.new(%w[doctor --config health.yml --seed 42], out: out, err: err).call).to eq(0)
  end

  it "describes doctor options in its own parser banner" do
    command = described_class.new(["doctor"], out: out, err: err)
    expect(command.send(:doctor_parser).to_s)
      .to include("Usage: saboteur doctor [--config PATH] [--seed N] [--suite] [--test PATH]")
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
