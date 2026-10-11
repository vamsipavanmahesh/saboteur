# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "json"

module Saboteur
  class Engine
    # Read-only identity for declared project inputs, not a Ruby dependency graph.
    # Capture before boot; verify before reuse/save. Unknown inputs are unsafe.
    class RunFingerprint
      FORMAT_VERSION = 1
      MANIFESTS = %w[Gemfile gems.rb Gemfile.lock gems.locked .rspec .rspec-local].freeze
      EXCLUDED_DIRECTORIES = %w[.git vendor node_modules].freeze
      Entry = Data.define(:path, :kind, :state, :sha256)
      Change = Data.define(:path, :reason)
      Snapshot = Data.define(:format_version, :digest, :inventory, :settings_digest, :runtime_digest, :complete,
                             :issues) do
        def to_h
          super.merge(inventory: inventory.map(&:to_h))
        end
      end
      Verification = Data.define(:unchanged, :complete, :current_digest, :changes, :issues)

      def self.restore_snapshot(hash)
        fields = hash.transform_keys(&:to_sym)
        validate_snapshot_fields(fields)
        inventory = fields.fetch(:inventory).map { |entry| restore_entry(entry) }.freeze
        raise ArgumentError, "duplicate inventory paths" unless inventory.map(&:path).uniq.size == inventory.size

        issues = fields.fetch(:issues).map { |issue| String(issue).dup.freeze }.freeze
        validate_snapshot_identity(fields, inventory, issues)
        frozen_fields = fields.transform_values { |value| value.is_a?(String) ? value.dup.freeze : value }
        Snapshot.new(**frozen_fields, inventory: inventory, issues: issues)
      rescue KeyError, TypeError, NoMethodError => e
        raise ArgumentError, "invalid fingerprint snapshot: #{e.class}"
      end

      def self.validate_snapshot_identity(fields, inventory, issues)
        raise ArgumentError, "invalid complete snapshot" if fields[:complete] && issues.any?
        raise ArgumentError, "unsorted inventory" unless inventory.map(&:path) == inventory.map(&:path).sort

        inputs = { format: FORMAT_VERSION, files: inventory.map(&:to_h),
                   settings: fields[:settings_digest], runtime: fields[:runtime_digest] }
        canonical = canonical_value(inputs)
        raise ArgumentError, "fingerprint identity mismatch" unless
          Digest::SHA256.hexdigest(JSON.generate(canonical)) == fields[:digest]
      end

      def self.validate_snapshot_fields(fields)
        raise ArgumentError, "unsupported fingerprint format" unless fields[:format_version] == FORMAT_VERSION
        raise ArgumentError, "invalid completeness" unless [true, false].include?(fields[:complete])

        %i[digest settings_digest runtime_digest].each do |key|
          raise ArgumentError, "invalid fingerprint digest" unless fields.fetch(key).match?(/\A[0-9a-f]{64}\z/)
        end
      end

      def self.restore_entry(entry)
        values = entry.transform_keys(&:to_sym)
        raise ArgumentError, "invalid fingerprint entry" unless valid_entry?(values)

        Entry.new(**values.transform_values { |value| value.is_a?(String) ? value.dup.freeze : value })
      end

      def self.valid_entry?(values)
        values.keys.sort == %i[kind path sha256 state] && values[:path].is_a?(String) &&
          %w[present missing unreadable].include?(values[:state]) && values[:kind].is_a?(String) &&
          (values[:sha256].nil? || values[:sha256].match?(/\A[0-9a-f]{64}\z/))
      end

      def self.runtime_identity
        { engine: RUBY_ENGINE, version: RUBY_VERSION, platform: RUBY_PLATFORM,
          patchlevel: RUBY_PATCHLEVEL, saboteur: VERSION }
      end

      def initialize(config:, root: config.root, extra_files: [], runtime_identity: self.class.runtime_identity)
        @config = config
        @root = File.realpath(root)
        @extra_files = extra_files.map do |file|
          options = file.is_a?(Hash) ? file : { path: file, required: true }
          [File.expand_path(options.fetch(:path), @root), options.fetch(:required, true)]
        end.freeze
        @runtime_identity = canonical(runtime_identity)
      end

      def snapshot
        issues = output_overlap_issues
        entries = inventory(issues).sort_by(&:path).freeze
        issues = issues.uniq.sort
        settings_digest = hash_value(@config.to_h)
        runtime_digest = hash_value(@runtime_identity)
        digest = hash_value(format: FORMAT_VERSION, files: entries.map(&:to_h),
                            settings: settings_digest, runtime: runtime_digest)
        Snapshot.new(format_version: FORMAT_VERSION, digest: digest, inventory: entries,
                     settings_digest: settings_digest, runtime_digest: runtime_digest,
                     complete: issues.empty?, issues: issues.freeze)
      end

      def verify(previous)
        current = snapshot
        changes = changes_between(previous, current)
        complete = previous.complete && current.complete && previous.format_version == FORMAT_VERSION
        Verification.new(unchanged: complete && previous.digest == current.digest,
                         complete: complete, current_digest: current.digest,
                         changes: changes.freeze, issues: current.issues)
      end

      def self.canonical_value(value)
        case value
        when Hash then value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonical_value(value[key])] }.freeze
        when Array then value.map { |entry| canonical_value(entry) }.freeze
        when String then value.dup.freeze
        else value
        end
      end

      private

      def output_overlap_issues
        paths = required_files.map(&:first)
        outputs = %w[json_report html_report].filter_map { |key| @config.fetch(key) }
                                             .map { |path| File.expand_path(path, @root) }
        issues = outputs.filter_map do |path|
          "output overlaps input: #{display_path(path)}" if path.end_with?(".rb") || paths.include?(path)
        end
        cache = @config.path("cache_dir")
        protected = [@root] + %w[app lib spec].map { |name| File.join(@root, name) } + paths
        if protected.any? { |path| path == cache || path.start_with?("#{cache}/") }
          issues << "cache directory overlaps inputs: #{display_path(cache)}"
        end
        issues
      end

      def inventory(issues)
        paths = project_files(issues).to_h { |path| [path, "ruby"] }
        MANIFESTS.each { |name| paths[File.join(@root, name)] = "manifest" }
        required = required_files.to_h { |path, kind, needed| [path, [kind, needed]] }
        required.each { |path, (kind, _)| paths[path] = kind }
        paths.map do |path, kind|
          needed = required.key?(path) ? required[path].last : kind != "manifest"
          read_entry(path, kind, needed, issues)
        end
      end

      # Walk without following symlink directories. A project symlink is an
      # undeclared dependency boundary, not a silently omitted source tree.
      def project_files(issues, directory = @root)
        Dir.children(directory).sort.flat_map do |name|
          path = File.join(directory, name)
          next [] if excluded?(path, name)

          if File.symlink?(path)
            issues << "symlink input: #{display_path(path)}".freeze
            next []
          end
          next project_files(issues, path) if File.directory?(path)

          File.file?(path) && path.end_with?(".rb") ? [path] : []
        end
      rescue SystemCallError
        issues << "unreadable directory: #{display_path(directory)}".freeze
        []
      end

      def excluded?(path, name)
        EXCLUDED_DIRECTORIES.include?(name) || path == @config.path("cache_dir") ||
          %w[json_report html_report].filter_map { |key| @config.fetch(key) }.any? do |output|
            path == File.expand_path(output, @root)
          end
      end

      def required_files
        paths = %w[require hooks].flat_map do |key|
          @config[key].map { |file| [resolve(file), key == "hooks" ? "hook" : "boot", true] }
        end
        paths += @config["sources"].reject { |entry| entry == "builtin" }.map do |entry|
          [resolve(entry.split(":", 2).first), "source_plugin", true]
        end
        paths + @extra_files.map { |path, needed| [path, "extra", needed] }
      end

      def resolve(file)
        path = File.expand_path(file, @root)
        return path if File.exist?(path) || File.extname(path) == ".rb"
        return "#{path}.rb" if File.exist?("#{path}.rb")

        path
      end

      def read_entry(path, kind, required, issues)
        name = display_path(path).freeze
        unless File.exist?(path)
          issues << "missing required input: #{name}".freeze if required
          return Entry.new(path: name, kind: kind.freeze, state: "missing", sha256: nil)
        end
        Entry.new(path: name, kind: kind.freeze, state: "present", sha256: Digest::SHA256.file(path).hexdigest.freeze)
      rescue SystemCallError, IOError
        issues << "unreadable input: #{name}".freeze
        Entry.new(path: name, kind: kind.freeze, state: "unreadable", sha256: nil)
      end

      def display_path(path)
        path.start_with?("#{@root}/") ? path.delete_prefix("#{@root}/") : "external:#{path}"
      end

      def changes_between(previous, current)
        before = previous.inventory.to_h { |entry| [entry.path, entry] }
        after = current.inventory.to_h { |entry| [entry.path, entry] }
        changes = (before.keys | after.keys).sort.filter_map do |path|
          next if before[path] == after[path]

          Change.new(path: path.freeze, reason: change_reason(before[path], after[path]))
        end
        if previous.settings_digest != current.settings_digest
          changes << Change.new(path: "settings",
                                reason: "changed")
        end
        changes << Change.new(path: "runtime", reason: "changed") if previous.runtime_digest != current.runtime_digest
        changes
      end

      def change_reason(before, after)
        return "added" unless before
        return "removed" unless after
        return "unreadable" if after.state == "unreadable"

        "changed"
      end

      def canonical(value)
        self.class.canonical_value(value)
      end

      def hash_value(value)
        Digest::SHA256.hexdigest(JSON.generate(canonical(value))).freeze
      end
    end
  end
end
