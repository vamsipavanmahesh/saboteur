# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rspec/core"
require "tmpdir"

# Which files the configured suite loads, by RSpec's own option and pattern
# rules, without loading any of them (#307).
RSpec.describe Saboteur::Integration::RSpec, "#configured_spec_files" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def write(path, text = "# x\n")
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), text)
  end

  def files(**values)
    config = Saboteur::Config.new(values.transform_keys(&:to_s), root: @root)
    described_class.new(config).configured_spec_files(@root)
  end

  before do
    write("spec/a_spec.rb")
    write("spec/requests/b_spec.rb")
    write("spec/fixtures/app/spec/wipe_spec.rb")
    write("spec/spec_helper.rb", "raise 'spec_helper must not load'\n")
    write("test/c_spec.rb")
  end

  it "lists the default path's spec files relative to the root" do
    expect(files.sort).to eq(%w[spec/a_spec.rb spec/fixtures/app/spec/wipe_spec.rb spec/requests/b_spec.rb])
  end

  it "applies the exclude pattern from .rspec" do
    write(".rspec", "--require spec_helper\n--exclude-pattern spec/fixtures/**/*_spec.rb\n")
    expect(files.sort).to eq(%w[spec/a_spec.rb spec/requests/b_spec.rb])
  end

  it "applies a pattern and paths from rspec_args" do
    write("spec/requests/d_feature.rb")
    expect(files(rspec_args: ["--pattern", "**/*_feature.rb", "spec/requests"])).to eq(%w[spec/requests/d_feature.rb])
  end

  # RSpec adds its default path only when $0 is rspec; saboteur is not.
  describe "under the saboteur executable" do
    around do |example|
      program = $PROGRAM_NAME
      $PROGRAM_NAME = "saboteur"
      example.run
    ensure
      $PROGRAM_NAME = program
    end

    it "still lists the default path when rspec_args holds only options and their values" do
      expect(files(rspec_args: %w[--require spec_helper]).sort)
        .to eq(%w[spec/a_spec.rb spec/fixtures/app/spec/wipe_spec.rb spec/requests/b_spec.rb])
      expect(files(rspec_args: ["--exclude-pattern", "spec/fixtures/**/*_spec.rb"]).sort)
        .to eq(%w[spec/a_spec.rb spec/requests/b_spec.rb])
      write("spec/requests/d_feature.rb")
      expect(files(rspec_args: ["--pattern", "**/*_feature.rb"])).to eq(%w[spec/requests/d_feature.rb])
    end

    it "lists the default path .rspec sets" do
      write(".rspec", "--default-path test\n")
      expect(files).to eq(%w[test/c_spec.rb])
    end
  end

  it "loads nothing and changes no global state: requires, load path, configuration and directory" do
    write(".rspec", "--require spec_helper\n-I extra\n--format NoSuchFormatter\n--pattern spec/**/*_spec.rb\n")
    load_path = $LOAD_PATH.dup
    pattern = RSpec.configuration.pattern
    directory = Dir.pwd
    expect { files }.not_to raise_error
    expect($LOAD_PATH).to eq(load_path)
    expect(RSpec.configuration.pattern).to eq(pattern)
    expect(Dir.pwd).to eq(directory)
  end

  it "returns UTF-8 paths, including non-ASCII names" do
    write("spec/café_spec.rb")
    listed = files
    expect(listed).to include("spec/café_spec.rb")
    expect(listed.map(&:encoding).uniq).to eq([Encoding::UTF_8])
  end
end

# Whether RSpec reads examples from spec/examples.txt, by RSpec's own option
# sources (#46).
RSpec.describe Saboteur::Integration::RSpec, "#status_file?" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(@root, "home"))
      saved = ENV.values_at("HOME", "SPEC_OPTS", "XDG_CONFIG_HOME")
      ENV["HOME"] = File.join(@root, "home")
      ENV.delete("SPEC_OPTS")
      ENV.delete("XDG_CONFIG_HOME")
      begin
        example.run
      ensure
        ENV["HOME"], ENV["SPEC_OPTS"], ENV["XDG_CONFIG_HOME"] = saved
      end
    end
  end

  def status_file?(**values)
    config = Saboteur::Config.new(values.transform_keys(&:to_s), root: @root)
    described_class.new(config).status_file?(@root)
  end

  it "is false for ordinary options" do
    File.write(File.join(@root, ".rspec"), "--format progress\n")

    expect(status_file?(rspec_args: ["--order", "defined"])).to be(false)
  end

  %w[--only-failures --next-failure --only-fail --next-fail --only].each do |flag|
    it "is true for the configured #{flag}" do
      expect(status_file?(rspec_args: [flag])).to be(true)
    end
  end

  it "is true for SPEC_OPTS" do
    ENV["SPEC_OPTS"] = "--only-failures"

    expect(status_file?).to be(true)
  end

  [[".rspec", "--format progress\n--only-failures\n"], [".rspec-local", "--next-failure\n"],
   ["home/.rspec", "--only-failures\n"], ["home/.config/rspec/options", "--next-failure\n"]].each do |name, text|
    it "is true for #{name}" do
      FileUtils.mkdir_p(File.dirname(File.join(@root, name)))
      File.write(File.join(@root, name), text)

      expect(status_file?).to be(true)
    end
  end

  it "is true for --options FILE" do
    File.write(File.join(@root, "mine"), "--only-failures\n")

    expect(status_file?(rspec_args: ["--options", "mine"])).to be(true)
  end
end
