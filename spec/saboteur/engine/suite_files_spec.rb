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

  it "digests the files' contents" do
    write("spec/spec_helper.rb", "1\n")
    first = described_class.new(Saboteur::Config.new({}, root: @root)).digest
    write("spec/spec_helper.rb", "2\n")
    expect(described_class.new(Saboteur::Config.new({}, root: @root)).digest).not_to eq(first)
  end
end
