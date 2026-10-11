# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"

module Saboteur
  # Writes the Rails starter files: .saboteur.yml, bin/saboteur and a
  # .gitignore entry. Plain Ruby so it runs and tests without Rails; the
  # `rails generate saboteur:install` generator is a thin wrapper over it.
  # Existing files are never overwritten unless force is set.
  class Install
    CONFIG = <<~YAML
      # saboteur configuration for a Rails + RSpec app. CLI flags override this file.
      include: [app/**/*.rb]
      # Empty base classes: nothing useful to mutate.
      exclude:
        - app/models/application_record.rb
        - app/controllers/application_controller.rb
        - app/jobs/application_job.rb
        - app/mailers/application_mailer.rb
      require: [./config/environment]   # boots the app before specs load
      rails: true                       # reconnect ActiveRecord after fork, per-worker databases
      jobs: 4                           # parallel workers; use 1 if your specs share external state
    YAML

    BIN = <<~RUBY
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      ENV["RAILS_ENV"] ||= "test"
      require "bundler/setup"
      load Gem.bin_path("saboteur", "saboteur")
    RUBY

    IGNORE_ENTRY = ".saboteur/"

    GEMFILE_HINT = <<~TEXT
      Add saboteur to your Gemfile if it is not there yet:

        group :test do
          gem "saboteur", require: false
        end

      Then run it with SimpleCov off for the run, for example:

        bin/saboteur run --since origin/main
    TEXT

    Result = Data.define(:status, :path)

    def initialize(root: Dir.pwd, force: false)
      @root = File.expand_path(root)
      @force = force
    end

    # Returns the list of Results (:created, :overwritten, :skipped, :appended, :unchanged).
    def call
      [write(".saboteur.yml", CONFIG), write("bin/saboteur", BIN, mode: 0o755), gitignore]
    end

    # Printed after install; the Gemfile is never edited.
    def gemfile_hint
      gemfile = File.join(@root, "Gemfile")
      return nil if File.file?(gemfile) && File.read(gemfile).match?(/^\s*gem\s+["']saboteur["']/)

      GEMFILE_HINT
    end

    private

    def write(relative, content, mode: nil)
      path = File.join(@root, relative)
      existed = File.exist?(path)
      return Result.new(:skipped, relative) if existed && !@force

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      File.chmod(mode, path) if mode
      Result.new(existed ? :overwritten : :created, relative)
    end

    def gitignore
      path = File.join(@root, ".gitignore")
      current = File.file?(path) ? File.read(path) : ""
      return Result.new(:unchanged, ".gitignore") if current.lines.map(&:strip).include?(IGNORE_ENTRY)

      separator = current.empty? || current.end_with?("\n") ? "" : "\n"
      File.write(path, "#{current}#{separator}#{IGNORE_ENTRY}\n")
      Result.new(:appended, ".gitignore")
    end
  end
end
