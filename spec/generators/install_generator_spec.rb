# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Stands in for Rails::Generators::Base: Rails is not in the bundle, so the
# generator file is loaded with the superclass stubbed and executed for real
# against a temp destination. One class, defined once: a second `load` of the
# generator would otherwise change its superclass.
class FakeRailsGeneratorBase
  def self.desc(*) = nil

  def self.class_option(*) = nil

  attr_reader :destination_root, :options, :said

  def initialize(destination_root, options)
    @destination_root = destination_root
    @options = options
    @said = []
  end

  def say(message) = (@said << message)

  def say_status(status, path) = (@said << [status, path])
end

RSpec.describe "saboteur:install generator" do
  def generate(root, with_ci:)
    stub_const("Rails::Generators::Base", FakeRailsGeneratorBase)
    # Neutralize the file's `require "rails/generators"`: Rails is not in the
    # bundle, so an empty stand-in on the load path satisfies the require.
    lib = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(lib, "rails"))
    File.write(File.join(lib, "rails/generators.rb"), "")
    $LOAD_PATH.unshift(lib)
    load File.expand_path("../../lib/generators/saboteur/install/install_generator.rb", __dir__)
    generator = Saboteur::Generators::InstallGenerator.new(root, { ci: with_ci, force: false })
    generator.install_saboteur
    generator
  end

  it "writes the starter files and the CI workflows, saying each status and the next step" do
    Dir.mktmpdir do |dir|
      generator = generate(dir, with_ci: true)
      expect(File).to exist(File.join(dir, "config/saboteur.rb"))
      expect(File).to exist(File.join(dir, "bin/saboteur"))
      expect(File).to exist(File.join(dir, ".github/workflows/saboteur-map.yml"))
      expect(File).to exist(File.join(dir, ".github/workflows/saboteur-pr.yml"))
      expect(generator.said).to include([:created, ".github/workflows/saboteur-map.yml"],
                                        [:created, ".github/workflows/saboteur-pr.yml"],
                                        "\n#{Saboteur::Install::Workflows::NEXT_STEP}")
    end
  end

  it "skips the CI workflows and the next step with --no-ci" do
    Dir.mktmpdir do |dir|
      generator = generate(dir, with_ci: false)
      expect(File).to exist(File.join(dir, "config/saboteur.rb"))
      expect(File).not_to exist(File.join(dir, ".github"))
      expect(generator.said.join).not_to include("Next:")
    end
  end

  it "is packaged where Rails looks for generators" do
    path = File.expand_path("../../lib/generators/saboteur/install/install_generator.rb", __dir__)
    expect(File.read(path)).to include("Saboteur::Install.new", "class InstallGenerator < Rails::Generators::Base")
  end

  it "writes the CI workflows too, unless --no-ci" do
    text = File.read(File.expand_path("../../lib/generators/saboteur/install/install_generator.rb", __dir__))
    expect(text).to include("installer.ci_workflows if options[:ci]", "class_option :ci")
  end

  it "is shipped in the gem files" do
    spec = Gem::Specification.load(File.expand_path("../../saboteur.gemspec", __dir__))
    expect(spec.files).to include("lib/generators/saboteur/install/install_generator.rb", "lib/saboteur/install.rb",
                                  "lib/saboteur/install/workflows.rb")
  end
end
