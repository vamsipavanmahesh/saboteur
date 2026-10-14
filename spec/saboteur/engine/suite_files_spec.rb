# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Engine::SuiteFiles do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def write(path, text = "x\n")
    File.join(@root, path).tap do |full|
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, text)
    end
  end

  def files(**settings)
    described_class.new(Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)).files
  end

  it "lists shared suite files but not example files" do
    helper = write("spec/spec_helper.rb")
    support = write("spec/support/db.rb")
    write("spec/models/user_spec.rb")
    expect(files).to include(helper, support)
    expect(files.grep(/_spec\.rb\z/)).to be_empty
  end

  it "lists boot files, hook files, .rspec and what .rspec or rspec_args require from outside spec/" do
    boot = write("config/boot.rb")
    hooks = write("config/saboteur_hooks.rb")
    rspec = write(".rspec", "--require test_setup\n")
    setup = write("lib/test_setup.rb")
    extra = write("lib/extra_setup.rb")
    listed = files(require: ["./config/boot"], hooks: ["config/saboteur_hooks.rb"],
                   rspec_args: ["--require", "extra_setup", "spec"])
    expect(listed).to include(boot, hooks, rspec, setup, extra)
  end

  it "reads glued -rNAME options and -I load path directories" do
    write(".rspec", "-rglued_setup -I support_dir --require=equals_setup\n")
    glued = write("lib/glued_setup.rb")
    equals = write("lib/equals_setup.rb")
    custom = write("support_dir/other_setup.rb")
    listed = files(rspec_args: ["--require", "other_setup"])
    expect(listed).to include(glued, equals, custom)
  end

  it "reads option files with non-ASCII tokens under a non-UTF-8 locale" do
    write(".rspec", "--require caf\u00E9_setup\n")
    allow(File).to receive(:read).and_wrap_original do |original, *args|
      original.call(*args).force_encoding(Encoding::US_ASCII)
    end
    expect { files }.not_to raise_error
  end

  it "digests the files' contents" do
    write("spec/spec_helper.rb", "1\n")
    first = described_class.new(Saboteur::Config.new({}, root: @root)).digest
    write("spec/spec_helper.rb", "2\n")
    expect(described_class.new(Saboteur::Config.new({}, root: @root)).digest).not_to eq(first)
  end
end

RSpec.describe Saboteur::Engine::SuiteFiles, "Rails data inputs" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def write(path, content)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def digest(extra = {})
    described_class.new(Saboteur::Config.new(extra, root: @root)).digest
  end

  %w[spec/fixtures/users.yml db/structure.sql config/database.yml].each do |path|
    it "changes the digest when #{path} changes" do
      write(path, "one")
      before = digest
      write(path, "two")
      expect(digest).not_to eq(before)
    end
  end

  it "does not change the digest for an unrelated file" do
    write("README.md", "one")
    before = digest
    write("README.md", "two")
    expect(digest).to eq(before)
  end

  it "tracks files matched by fingerprint_extra" do
    write("data/seed.csv", "one")
    ignored = digest
    before = digest("fingerprint_extra" => ["data/*.csv"])
    write("data/seed.csv", "two")
    expect(digest("fingerprint_extra" => ["data/*.csv"])).not_to eq(before)
    expect(digest).to eq(ignored) # without the key the file is ignored
  end
end
