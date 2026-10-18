# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::CustomMap do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def write_map(body)
    FileUtils.mkdir_p(File.join(@root, "config"))
    path = File.join(@root, "config", "saboteur_custom_map.rb")
    File.write(path, body)
    path
  end

  def load(body)
    described_class.load(write_map(body), root: @root)
  end

  def touch(relative)
    path = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# x\n")
  end

  it "is empty when the file is absent" do
    map = described_class.load(File.join(@root, "config", "saboteur_custom_map.rb"), root: @root)
    expect(map).to be_empty
    expect(map.specs_for("app/models/order.rb")).to be_nil
  end

  it "maps an exact path" do
    touch("spec/services/tax_sync_spec.rb")
    map = load(<<~RUBY)
      SABOTEUR_CUSTOM_MAP = { "app/services/tax_sync.rb" => ["spec/services/tax_sync_spec.rb"] }.freeze
    RUBY
    expect(map.specs_for("app/services/tax_sync.rb")).to eq(["spec/services/tax_sync_spec.rb"])
    expect(map.specs_for("app/services/other.rb")).to be_nil
  end

  it "maps globs and prefers the more specific one" do
    touch("spec/services/tax_sync_spec.rb")
    touch("spec/services/x_spec.rb")
    map = load(<<~RUBY)
      SABOTEUR_CUSTOM_MAP = {
        "app/services/**/*.rb" => ["spec/services/x_spec.rb"],
        "app/services/tax_*.rb" => ["spec/services/tax_sync_spec.rb"],
      }.freeze
    RUBY
    expect(map.specs_for("app/services/tax_sync.rb")).to eq(["spec/services/tax_sync_spec.rb"])
    expect(map.specs_for("app/services/other.rb")).to eq(["spec/services/x_spec.rb"])
  end

  it "prefers an exact key over a glob" do
    touch("spec/a_spec.rb")
    touch("spec/b_spec.rb")
    map = load(<<~RUBY)
      SABOTEUR_CUSTOM_MAP = {
        "app/**/*.rb" => ["spec/a_spec.rb"],
        "app/order.rb" => ["spec/b_spec.rb"],
      }.freeze
    RUBY
    expect(map.specs_for("app/order.rb")).to eq(["spec/b_spec.rb"])
  end

  it "fails on equally specific glob keys matching the same file" do
    touch("spec/a_spec.rb")
    touch("spec/b_spec.rb")
    map = load(<<~RUBY)
      SABOTEUR_CUSTOM_MAP = {
        "app/m?dels/order.rb" => ["spec/a_spec.rb"],
        "app/?odels/order.rb" => ["spec/b_spec.rb"],
      }.freeze
    RUBY
    expect { map.specs_for("app/models/order.rb") }
      .to raise_error(Saboteur::ConfigError, %r{both match app/models/order\.rb.*equal specificity})
  end

  it "fills regexp captures into the spec paths" do
    map = load(<<~'RUBY')
      SABOTEUR_CUSTOM_MAP = { %r{\Aapp/jobs/(.*)\.rb\z} => ['spec/jobs/\1_spec.rb'] }.freeze
    RUBY
    expect(map.specs_for("app/jobs/billing/charge.rb")).to eq(["spec/jobs/billing/charge_spec.rb"])
  end

  it "names unsupported named templates when their literal path is absent (#642)" do
    path = write_map(<<~'RUBY')
      SABOTEUR_CUSTOM_MAP = { %r{\Alib/(?<path>.+)\.rb\z} => ["spec/unit/%<path>s_spec.rb"] }.freeze
    RUBY
    expect { described_class.load(path, root: @root) }.to raise_error(Saboteur::ConfigError) { |error|
      key = %r{\Alib/(?<path>.+)\.rb\z}
      expect(error.message).to eq("#{path}: #{key.inspect} maps to #{'spec/unit/%<path>s_spec.rb'.inspect}; " \
                                  'regex map specs support \1 backreferences only')
      expect(error.message).not_to include("matches no file")
    }
  end

  # rubocop:disable Style/FormatStringToken -- unsupported syntax is the input under test
  ["%{p}", '\k<p>', "%-10<a>s", "%<a-b>s"].each do |template|
    it "names the unsupported #{template} template when missing (#642)" do
      body = "SABOTEUR_CUSTOM_MAP = { /lib/ => [#{"spec/#{template}_spec.rb".dump}] }"
      expect { load(body) }.to raise_error(Saboteur::ConfigError, /regex map specs support/)
    end
  end

  # rubocop:enable Style/FormatStringToken

  it "keeps a real literal percent-angle file under a Regexp key (#642)" do
    touch("spec/%<name>s_spec.rb")
    map = load('SABOTEUR_CUSTOM_MAP = { /lib/ => ["spec/%<name>s_spec.rb"] }')
    expect(map.specs_for("lib/a.rb")).to eq(["spec/%<name>s_spec.rb"])
  end

  it "uses the ordinary missing-file error for a String key with named-template text (#642)" do
    expect do
      load('SABOTEUR_CUSTOM_MAP = { "lib/a.rb" => ["spec/%<missing>s_spec.rb"] }')
    end.to raise_error(Saboteur::ConfigError, /matches no file/)
  end

  it "does not diagnose empty percent-angle text as a named template when missing (#642)" do
    expect do
      load('SABOTEUR_CUSTOM_MAP = { /lib/ => ["spec/%<>s_spec.rb"] }')
    end.to raise_error(Saboteur::ConfigError, /matches no file/)
  end

  it "does not mistake empty percent-angle text for a named template (#642)" do
    touch("spec/%<>s_spec.rb")
    map = load('SABOTEUR_CUSTOM_MAP = { /lib/ => ["spec/%<>s_spec.rb"] }')
    expect(map.specs_for("lib/a.rb")).to eq(["spec/%<>s_spec.rb"])
  end

  it "keeps percent-angle text literal under a String key (#642)" do
    touch("spec/%<path>s_spec.rb")
    map = load('SABOTEUR_CUSTOM_MAP = { "lib/a.rb" => ["spec/%<path>s_spec.rb"] }')
    expect(map.specs_for("lib/a.rb")).to eq(["spec/%<path>s_spec.rb"])
  end

  it "marks an empty array as excluded by config" do
    map = load(<<~RUBY)
      SABOTEUR_CUSTOM_MAP = { "app/generated/**/*.rb" => [] }.freeze
    RUBY
    expect(map.specs_for("app/generated/client.rb")).to eq(:excluded)
  end

  it "requires the constant to be a Hash" do
    expect { load("SABOTEUR_CUSTOM_MAP = []\n") }
      .to raise_error(Saboteur::ConfigError, /must be a Hash, got Array/)
  end

  it "requires the constant to be defined" do
    expect { load("OTHER = {}\n") }
      .to raise_error(Saboteur::ConfigError, /expected it to define SABOTEUR_CUSTOM_MAP/)
  end

  it "rejects a non-String non-Regexp key" do
    touch("spec/a_spec.rb")
    expect { load("SABOTEUR_CUSTOM_MAP = { 42 => [\"spec/a_spec.rb\"] }.freeze\n") }
      .to raise_error(Saboteur::ConfigError, /key 42 must be a String path, glob, or Regexp/)
  end

  it "rejects a bare String value" do
    expect { load("SABOTEUR_CUSTOM_MAP = { \"app/a.rb\" => \"spec/a_spec.rb\" }.freeze\n") }
      .to raise_error(Saboteur::ConfigError, /wrap spec paths in an array/)
  end

  it "rejects a spec path outside the project root" do
    expect { load("SABOTEUR_CUSTOM_MAP = { \"app/a.rb\" => [\"../outside_spec.rb\"] }.freeze\n") }
      .to raise_error(Saboteur::ConfigError, /outside the project root/)
  end

  it "rejects a spec path that matches no file" do
    expect { load("SABOTEUR_CUSTOM_MAP = { \"app/a.rb\" => [\"spec/missing_spec.rb\"] }.freeze\n") }
      .to raise_error(Saboteur::ConfigError, %r{maps to "spec/missing_spec.rb", which matches no file})
  end

  it "reports a syntax error with the file" do
    expect { load("SABOTEUR_CUSTOM_MAP = {\n") }
      .to raise_error(Saboteur::ConfigError, /saboteur_custom_map\.rb/)
  end

  it "is empty when the path is nil" do
    expect(described_class.load(nil, root: @root)).to be_empty
  end

  it "reloads without an already-initialized warning" do
    touch("spec/services/tax_sync_spec.rb")
    path = write_map("SABOTEUR_CUSTOM_MAP = { \"app/a.rb\" => [\"spec/services/tax_sync_spec.rb\"] }.freeze\n")
    original_stderr = $stderr
    $stderr = StringIO.new
    2.times { described_class.load(path, root: @root) }
    warnings = $stderr.string
    $stderr = original_stderr
    expect(warnings).not_to include("already initialized")
  end

  it "is not empty once entries are loaded" do
    touch("spec/services/tax_sync_spec.rb")
    map = load(<<~RUBY)
      SABOTEUR_CUSTOM_MAP = { "app/a.rb" => ["spec/services/tax_sync_spec.rb"] }.freeze
    RUBY
    expect(map).not_to be_empty
  end

  it "rejects a non-String spec entry" do
    expect { load("SABOTEUR_CUSTOM_MAP = { \"app/a.rb\" => [42] }.freeze\n") }
      .to raise_error(Saboteur::ConfigError, /spec paths must be Strings/)
  end

  it "takes a backreference literally under a String key" do
    expect { load(%(SABOTEUR_CUSTOM_MAP = { "app/a.rb" => ["spec/\\1_spec.rb"] }.freeze\n)) }
      .to raise_error(Saboteur::ConfigError, /matches no file/)
  end

  it "checks a backreference-shaped spec literally under a String key" do
    expect { load(%(SABOTEUR_CUSTOM_MAP = { "app/a.rb" => ['spec/\\1_spec.rb'] }.freeze\n)) }
      .to raise_error(Saboteur::ConfigError, /matches no file/)
  end

  it "still checks a static spec path under a Regexp key" do
    expect { load(%(SABOTEUR_CUSTOM_MAP = { %r{app} => ["spec/missing_spec.rb"] }.freeze\n)) }
      .to raise_error(Saboteur::ConfigError, /matches no file/)
  end

  it "prefers an exact key over a glob with more literal characters" do
    touch("spec/a_spec.rb")
    touch("spec/b_spec.rb")
    map = load(<<~RUBY)
      SABOTEUR_CUSTOM_MAP = {
        "app/order.rb" => ["spec/b_spec.rb"],
        "app/**/order.rb" => ["spec/a_spec.rb"],
      }.freeze
    RUBY
    expect(map.specs_for("app/order.rb")).to eq(["spec/b_spec.rb"])
  end

  it "ignores a Regexp key that does not match" do
    touch("spec/a_spec.rb")
    map = load(<<~'RUBY')
      SABOTEUR_CUSTOM_MAP = { %r{\Anothing/} => ["spec/a_spec.rb"] }.freeze
    RUBY
    expect(map.specs_for("app/order.rb")).to be_nil
  end

  it "marks a Regexp entry with an empty array as excluded by config" do
    map = load(<<~'RUBY')
      SABOTEUR_CUSTOM_MAP = { %r{\Aapp/generated/} => [] }.freeze
    RUBY
    expect(map.specs_for("app/generated/client.rb")).to eq(:excluded)
  end

  it "keeps the mapped specs when only some matching Regexp entries are empty" do
    map = load(<<~'RUBY')
      SABOTEUR_CUSTOM_MAP = {
        %r{\Aapp/generated/} => [],
        %r{\Aapp/generated/(.*)\.rb\z} => ['spec/generated/\1_spec.rb'],
      }.freeze
    RUBY
    expect(map.specs_for("app/generated/client.rb")).to eq(["spec/generated/client_spec.rb"])
  end

  it "still excludes when every matching Regexp entry is empty" do
    map = load(<<~'RUBY')
      SABOTEUR_CUSTOM_MAP = { %r{\Aapp/generated/} => [], %r{client} => [] }.freeze
    RUBY
    expect(map.specs_for("app/generated/client.rb")).to eq(:excluded)
  end

  it "drops a backreference whose group did not participate" do
    map = load(<<~'RUBY')
      SABOTEUR_CUSTOM_MAP = { %r{\Aapp/(admin/)?client\.rb\z} => ['\1'] }.freeze
    RUBY
    expect(map.specs_for("app/client.rb")).to eq([])
  end

  it "wraps a bare call in the map file with file, line and the load-order hint" do
    path = write_map("bogus_call\n")
    expect { described_class.load(path, root: @root) }.to raise_error(Saboteur::ConfigError) { |error|
      expect(error.message).to include("saboteur_custom_map.rb:1", "bogus_call", "before the app boots")
    }
  end

  it "names both keys in the equal-specificity error" do
    touch("spec/a_spec.rb")
    touch("spec/b_spec.rb")
    map = load(<<~RUBY)
      SABOTEUR_CUSTOM_MAP = {
        "app/m?dels/order.rb" => ["spec/a_spec.rb"],
        "app/?odels/order.rb" => ["spec/b_spec.rb"],
      }.freeze
    RUBY
    pattern = %r{custom map keys "app/m\?dels/order.rb" and "app/\?odels/order.rb" both match .* equal specificity}
    expect { map.specs_for("app/models/order.rb") }.to raise_error(Saboteur::ConfigError, pattern)
  end

  it "lists stale keys that match no file" do
    touch("spec/a_spec.rb")
    touch("app/models/order.rb")
    map = load(<<~RUBY)
      SABOTEUR_CUSTOM_MAP = {
        "app/models/order.rb" => ["spec/a_spec.rb"],
        "app/models/gone.rb" => ["spec/a_spec.rb"],
      }.freeze
    RUBY
    expect(map.stale_keys).to eq(["app/models/gone.rb"])
  end

  it "spots literal keys written twice" do
    touch("spec/a_spec.rb")
    path = write_map(<<~RUBY)
      SABOTEUR_CUSTOM_MAP = {
        "app/models/order.rb" => ["spec/a_spec.rb"],
        "app/models/order.rb" => ["spec/a_spec.rb"],
        "app/models/user.rb" => ["spec/a_spec.rb"],
      }.freeze
    RUBY
    map = described_class.load(path, root: @root)
    expect(map.duplicate_keys(path)).to eq(["app/models/order.rb"])
  end

  it "scans a map with non-ASCII content under a non-UTF-8 locale" do
    touch("lib/a.rb")
    touch("spec/a_spec.rb")
    path = write_map("# caf\u00E9 comment\nSABOTEUR_CUSTOM_MAP = { \"lib/a.rb\" => [\"spec/a_spec.rb\"] }.freeze\n")
    map = described_class.load(path, root: @root)
    allow(File).to receive(:readlines).and_wrap_original do |original, *args|
      original.call(*args).map { |line| line.force_encoding(Encoding::US_ASCII) }
    end
    expect(map.duplicate_keys(path)).to eq([])
  end

  it "never treats a String key as a Regexp" do
    touch("spec/x_spec.rb")
    map = load("SABOTEUR_CUSTOM_MAP = { \"lib/userXrb\" => [\"spec/x_spec.rb\"] }.freeze\n")
    expect(map.specs_for("lib/user.rb")).to be_nil
  end

  it "keeps the root when the file is absent" do
    map = described_class.load(File.join(@root, "config", "saboteur_custom_map.rb"), root: @root)
    expect(map.root).to eq(@root)
  end

  it "clears a pre-defined constant before loading and after" do
    Object.const_set(:SABOTEUR_CUSTOM_MAP, { "stale" => [] }.freeze)
    map = nil
    expect { map = load("SABOTEUR_CUSTOM_MAP = { \"app/a.rb\" => [] }.freeze\n") }
      .not_to output(/already initialized/).to_stderr
    expect(map.specs_for("app/a.rb")).to eq(:excluded)
    expect(Object.const_defined?(:SABOTEUR_CUSTOM_MAP)).to be(false)
  ensure
    Object.send(:remove_const, :SABOTEUR_CUSTOM_MAP) if Object.const_defined?(:SABOTEUR_CUSTOM_MAP)
  end
end
