# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require_relative "text"
require_relative "install/workflows"

module Saboteur
  # Writes the Rails starter files: config/saboteur.rb, bin/saboteur and a
  # .gitignore entry. Plain Ruby so it runs and tests without Rails; the
  # `rails generate saboteur:install` generator is a thin wrapper over it.
  # Existing files are never overwritten unless force is set.
  class Install
    CONFIG = <<~RUBY
      # saboteur configuration for a Rails + RSpec app. CLI flags override this file.
      # Only the decisions a first run needs are set here; every other key keeps
      # its default. Who changes what, key by key:
      # https://github.com/vamsipavanmahesh/saboteur/blob/main/docs/config-keys.md
      Saboteur.configure do |c|
        # First-run decision: what to mutate.
        c.include = ["app/**/*.rb"]
        # Empty base classes: nothing useful to mutate.
        c.exclude = [
          "app/models/application_record.rb",
          "app/controllers/application_controller.rb",
          "app/jobs/application_job.rb",
          "app/mailers/application_mailer.rb",
        ]
        c.require = ["./config/environment"] # boots the app before specs load
        c.rails = true                       # reconnect ActiveRecord after fork, per-worker databases
        # First-run decision: parallelism; use 1 if your specs share external state.
        c.jobs = 4
      end
    RUBY

    BASE_CLASSES = %w[app/models/application_record.rb app/controllers/application_controller.rb
                      app/jobs/application_job.rb app/mailers/application_mailer.rb].freeze

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
      [write("config/saboteur.rb", config_text), write("bin/saboteur", BIN, mode: 0o755), gitignore]
    end

    # The two CI workflows for the whole-suite map (#1317). An existing file
    # is never overwritten, even with force: a workflow is the project's own.
    def ci_workflows
      ruby_pinned = File.file?(File.join(@root, ".ruby-version")) || File.file?(File.join(@root, ".tool-versions"))
      Workflows.files(ruby_version_file: ruby_pinned).map do |relative, text|
        write(relative, text, force: false)
      end
    end

    RUN_HINT = "Next: bin/saboteur doctor, then bin/saboteur run --since origin/main " \
               "(keep SimpleCov off for the run)."

    # Printed after install; the Gemfile is never edited. The run pointer is
    # always due: the Gemfile block only when the gem is missing.
    def gemfile_hint
      gemfile = File.join(@root, "Gemfile")
      return RUN_HINT if File.file?(gemfile) && Text.utf8(File.read(gemfile)).match?(/^\s*gem\s+["']saboteur["']/)

      GEMFILE_HINT
    end

    private

    # CONFIG without the base-class excludes this app does not have: a
    # minimal Rails app has no ApplicationJob or ApplicationMailer, and an
    # exclude that matches no file makes doctor and every run warn.
    def config_text
      BASE_CLASSES.reject { |path| File.exist?(File.join(@root, path)) }
                  .reduce(CONFIG) { |text, path| text.sub(%(    "#{path}",\n), "") }
    end

    # Never writes or chmods through a symlink: not the file itself, and not a
    # symlinked directory above it (bin -> elsewhere). Without force the file is
    # skipped; with force the link is removed and replaced by a real file or
    # directory inside the project, and the old target is left alone.
    def write(relative, content, mode: nil, force: @force)
      path = File.join(@root, relative)
      link = symlink_component(relative)
      existed = present?(path)
      return Result.new(:skipped, relative) if (existed || link) && !force

      File.delete(link) if link
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      File.chmod(mode, path) if mode
      Result.new(existed ? :overwritten : :created, relative)
    end

    # The first symlink on the way from the project root to the file, if any.
    def symlink_component(relative)
      current = @root
      relative.split("/").each do |part|
        current = File.join(current, part)
        return current if File.symlink?(current)
      end
      nil
    end

    # A dangling symlink does not "exist" but is not free to write either.
    def present?(path)
      File.exist?(path) || File.symlink?(path)
    end

    def gitignore
      path = File.join(@root, ".gitignore")
      link = symlink_component(".gitignore")
      return Result.new(:skipped, ".gitignore") if link && !@force

      current = File.file?(path) ? Text.utf8_identity(File.read(path)) : ""
      listed = listed?(Text.utf8(current))
      return Result.new(:unchanged, ".gitignore") if listed && !link

      File.delete(link) if link
      File.write(path, "#{current}#{missing_entry(current, listed)}")
      Result.new(link ? :overwritten : :appended, ".gitignore")
    end

    def listed?(text)
      text.lines.map(&:strip).include?(IGNORE_ENTRY)
    end

    # What to append so .saboteur/ is on its own line; nothing if already there.
    def missing_entry(current, listed)
      return "" if listed

      separator = current.empty? || current.end_with?("\n") ? "" : "\n"
      "#{separator}#{IGNORE_ENTRY}\n"
    end
  end
end
