# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "json"
require_relative "../config"
require_relative "../text"
require_relative "data_inputs"

module Saboteur
  class Engine
    # Read-only identity for declared project inputs, not a Ruby dependency graph.
    # Capture before boot; verify before reuse/save. Unknown inputs are unsafe.
    class RunFingerprint
      FORMAT_VERSION = 1
      MANIFESTS = %w[Gemfile gems.rb Gemfile.lock gems.locked .rspec .rspec-local].freeze
      LOCATION_SETTINGS = Config::OUTPUT_KEYS + Config::PRESENTATION_KEYS
      ENTRY_KINDS = %w[ruby manifest boot hook source_plugin extra data].freeze
      EXCLUDED_DIRECTORIES = %w[.git vendor node_modules].freeze
      Entry = Data.define(:path, :kind, :state, :sha256, :required)
      Change = Data.define(:path, :reason)
      Snapshot = Data.define(:format_version, :digest, :inventory, :settings_digest, :runtime_digest, :complete,
                             :issues) do
        def to_h
          super.merge(inventory: inventory.map(&:to_h))
        end
      end
      Verification = Data.define(:unchanged, :complete, :current_digest, :changes, :issues)

      def self.restore_snapshot(hash)
        fields = canonical_mapping(hash).transform_keys(&:to_sym)
        validate_snapshot_fields(fields)
        inventory = fields.fetch(:inventory).map { |entry| restore_entry(entry) }.freeze
        raise ArgumentError, "duplicate inventory paths" unless inventory.map(&:path).uniq.size == inventory.size

        issues = restore_issues(fields.fetch(:issues))
        validate_snapshot_identity(fields, inventory, issues)
        Snapshot.new(**fields, inventory: inventory, issues: issues)
      rescue KeyError, TypeError, NoMethodError => e
        raise ArgumentError, "invalid fingerprint snapshot: #{e.class}"
      end

      def self.restore_issues(issues)
        raise ArgumentError, "invalid issues" unless
          issues.is_a?(Array) && issues.all?(String) && issues == issues.uniq.sort

        issues.map { |issue| issue.dup.freeze }.freeze
      end

      def self.validate_snapshot_identity(fields, inventory, issues)
        raise ArgumentError, "invalid complete snapshot" if
          fields[:complete] && (issues.any? || inventory.any? do |entry|
            entry.state == "unreadable" || (entry.required && entry.state == "missing")
          end)
        raise ArgumentError, "unsorted inventory" unless inventory.map(&:path) == inventory.map(&:path).sort

        inputs = { format: FORMAT_VERSION, files: inventory.map(&:to_h),
                   settings: fields[:settings_digest], runtime: fields[:runtime_digest] }
        canonical = canonical_value(inputs)
        raise ArgumentError, "fingerprint identity mismatch" unless
          Digest::SHA256.hexdigest(JSON.generate(canonical)) == fields[:digest]
      end

      def self.validate_snapshot_fields(fields)
        raise ArgumentError, "invalid snapshot fields" unless fields.keys.sort == Snapshot.members.sort
        raise ArgumentError, "unsupported fingerprint format" unless fields[:format_version] == FORMAT_VERSION
        raise ArgumentError, "invalid completeness" unless [true, false].include?(fields[:complete])

        %i[digest settings_digest runtime_digest].each do |key|
          raise ArgumentError, "invalid fingerprint digest" unless fields.fetch(key).match?(/\A[0-9a-f]{64}\z/)
        end
      end

      def self.restore_entry(entry)
        values = canonical_mapping(entry).transform_keys(&:to_sym)
        raise ArgumentError, "invalid fingerprint entry" unless valid_entry?(values)

        Entry.new(**values)
      end

      def self.valid_entry?(values)
        values.keys.sort == %i[kind path required sha256 state] && valid_path?(values[:path]) &&
          [true,
           false].include?(values[:required]) && ENTRY_KINDS.include?(values[:kind]) &&
          (!%w[ruby boot hook
               source_plugin].include?(values[:kind]) || values[:required]) && valid_state?(values[:state],
                                                                                            values[:sha256])
      end

      def self.valid_path?(path)
        unless path.is_a?(String) && !path.empty? && !path.include?("\0") &&
               !path.include?("\\") && !path.end_with?("/")
          return false
        end

        candidate = path.delete_prefix("external:")
        absolute = path.start_with?("external:")
        return false unless candidate.start_with?("/") == absolute

        segments = candidate.split("/")
        segments.shift if absolute
        segments.none? { |part| part.empty? || %w[. ..].include?(part) }
      end

      def self.valid_state?(state, digest)
        return digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/) if state == "present"

        %w[missing unreadable].include?(state) && digest.nil?
      end

      def self.runtime_identity
        { engine: RUBY_ENGINE, version: RUBY_VERSION, platform: RUBY_PLATFORM,
          patchlevel: RUBY_PATCHLEVEL, saboteur: VERSION }
      end

      def initialize(config:, root: config.root, extra_files: [], runtime_identity: self.class.runtime_identity)
        @config = config
        @root = File.realpath(root)
        raise ArgumentError, "root differs from config.root" unless @root == File.realpath(config.root)

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
        settings_digest = hash_value(@config.selection_settings.except(*LOCATION_SETTINGS))
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
        when Hash then canonical_mapping(value)
        when Array then value.map { |entry| canonical_value(entry) }.freeze
        when String then value.dup.freeze
        when NilClass, TrueClass, FalseClass, Integer then value
        when Float
          raise ArgumentError, "non-finite identity number" unless value.finite?

          value
        else raise ArgumentError, "unsupported identity value"
        end
      end

      def self.canonical_mapping(value)
        raise ArgumentError, "invalid identity key" unless value.keys.all? do |key|
          key.is_a?(String) || key.is_a?(Symbol)
        end
        raise ArgumentError, "duplicate normalized identity key" unless value.keys.map(&:to_s).uniq.size == value.size

        value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonical_value(value[key])] }.freeze
      end

      private

      def canonical_path(path)
        expanded = File.expand_path(path, @root)
        return File.realpath(expanded) if File.exist?(expanded)

        parent = File.dirname(expanded)
        File.join(canonical_path(parent), File.basename(expanded))
      end

      def output_overlap_issues
        paths = required_files.map(&:first) + MANIFESTS.map { |name| File.join(@root, name) } +
                DataInputs.files(@root, extra: @config["fingerprint_extra"])
        # Compare physical boundaries without changing declared inventory identities.
        paths = paths.map { |path| canonical_path(path) }.uniq
        outputs = %w[json_report html_report score_history].filter_map { |key| @config.fetch(key) }
                                                           .map { |path| canonical_path(path) }
        issues = outputs.filter_map do |path|
          if path.end_with?(".rb") || paths.include?(path) || File.directory?(path) || data_input?(path)
            "output overlaps input: #{display_path(path)}"
          end
        end
        issues.concat(cache_overlap_issues(paths))
        issues
      end

      def cache_overlap_issues(paths)
        cache = canonical_path(@config["cache_dir"])
        protected = [@root] + %w[app lib spec test/fixtures].map { |name| File.join(@root, name) } + paths
        inside = protected.any? do |path|
          path == cache || path.start_with?("#{cache}/") || (path != @root && cache.start_with?("#{path}/"))
        end
        overlaps = inside || data_input?(cache)
        overlaps ? ["cache directory overlaps inputs: #{display_path(cache)}"] : []
      end

      # Declared fixture, schema or config input, or a path inside a fixture tree.
      def data_input?(path)
        DataInputs.match?(@root, path, extra: @config["fingerprint_extra"])
      end

      def inventory(issues)
        paths = project_files(issues).to_h { |path| [path, "ruby"] }
        MANIFESTS.each { |name| paths[File.join(@root, name)] = "manifest" }
        data_files(issues).each { |path| paths[path] ||= "data" }
        required = merged_required_files
        required.each { |path, (kind, _)| paths[path] = kind }
        paths.map do |path, kind|
          needed = required.key?(path) ? required[path].last : !%w[manifest data].include?(kind)
          read_entry(path, kind, needed, issues)
        end
      end

      # Fixtures, schema dumps and database config. A pattern with no match is
      # fine; a listed file that vanishes later shows up as "removed". Like Ruby
      # files, data reached through a symlink (the file or a directory above it)
      # is an undeclared boundary: its real path could be an output or lie outside
      # the project, so the snapshot is incomplete instead of guessing.
      def data_files(issues)
        DataInputs.files(@root, extra: @config["fingerprint_extra"]).reject do |path|
          next false unless symlinked?(path)

          issues << "symlink input: #{display_path(path)}".freeze
          true
        end
      end

      def symlinked?(path)
        current = @root
        path.delete_prefix("#{@root}/").split("/").any? { |part| File.symlink?(current = File.join(current, part)) }
      end

      def merged_required_files
        required_files.group_by(&:first).transform_values do |entries|
          roles = entries.map { |_, kind, _| kind }
          role = (roles - ["extra"]).min || "extra"
          [role, entries.any? { |_, _, needed| needed }]
        end
      end

      # Walk without following symlink directories. A project symlink is an
      # undeclared dependency boundary, not a silently omitted source tree.
      def project_files(issues, directory = @root)
        Dir.children(directory).sort.flat_map do |name|
          # Child names arrive locale-tagged; retag losslessly before
          # joining with the UTF-8 root (#231).
          name = Text.utf8_identity(name)
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
        EXCLUDED_DIRECTORIES.include?(name) || path == canonical_path(@config["cache_dir"]) ||
          %w[json_report html_report score_history].filter_map { |key| @config.fetch(key) }.any? do |output|
            path == canonical_path(output)
          end
      end

      def required_files
        paths = %w[require hooks].flat_map do |key|
          @config[key].map { |file| [resolve(file), key == "hooks" ? "hook" : "boot", true] }
        end
        paths += @config["sources"].reject { |entry| entry == "builtin" }.map do |entry|
          [resolve(entry.partition(":").first), "source_plugin", true]
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
          return Entry.new(path: name, kind: kind.freeze, state: "missing", sha256: nil, required: required)
        end
        Entry.new(path: name, kind: kind.freeze, state: "present", sha256: Digest::SHA256.file(path).hexdigest.freeze,
                  required: required)
      rescue SystemCallError, IOError
        issues << "unreadable input: #{name}".freeze
        Entry.new(path: name, kind: kind.freeze, state: "unreadable", sha256: nil, required: required)
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
