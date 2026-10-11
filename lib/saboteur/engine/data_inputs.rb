# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Non-Ruby files a test run can read and that change its outcome: Rails
    # fixtures, schema dumps and database/environment configuration, plus
    # anything listed under `fingerprint_extra`. Ruby files are tracked
    # elsewhere; these have no .rb extension, so the Ruby walk misses them.
    # An absent pattern simply matches nothing, so plain gems are unaffected.
    module DataInputs
      GLOBS = %w[
        spec/fixtures/**/*
        spec/**/fixtures/**/*
        test/fixtures/**/*
        db/structure.sql
        db/schema.rb
        config/database.yml
        config/database.yml.erb
        config/*.yml
        config/environments/*.yml
        config/credentials/*.yml.enc
      ].freeze

      # True when the absolute path is one of the declared inputs, whether or
      # not the file exists yet. A run must never write there.
      def self.match?(root, path, extra: [])
        return false unless path.start_with?("#{root}/")

        relative = path.delete_prefix("#{root}/")
        flags = File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB
        (GLOBS + extra).any? { |pattern| File.fnmatch?(pattern, relative, flags) }
      end

      # Sorted absolute paths of regular files (symlinks followed) under root.
      def self.files(root, extra: [])
        (GLOBS + extra).flat_map { |pattern| Dir.glob(pattern, File::FNM_DOTMATCH, base: root) }
                       .map { |relative| File.join(root, relative) }
                       .select { |path| File.file?(path) }.uniq.sort
      end
    end
  end
end
