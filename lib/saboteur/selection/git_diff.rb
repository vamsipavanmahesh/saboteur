# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require_relative "../text"
require_relative "layout_only_lines"
require_relative "untracked_changes"

module Saboteur
  module Selection
    # Lines changed between the merge base of REF and HEAD, plus uncommitted
    # changes, as { "/abs/path.rb" => Set[line numbers in the current file] }.
    module GitDiff
      NO_FILE = "/dev/null" # rubocop:disable Style/FileNull -- literal in git diff output
      HUNK = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

      module_function

      # Fails before any boot work when REF is not a commit here, as a usage
      # error (exit 2): the name is wrong, or a shallow checkout lacks it.
      def verify_ref!(ref, root:)
        raise ConfigError, "--since needs a git ref, not an option: #{ref}" if ref.start_with?("-")

        _, _, inside = Open3.capture3("git", "rev-parse", "--git-dir", chdir: root)
        raise ConfigError, "--since needs a git repository" unless inside.success?

        _, _, found = Open3.capture3("git", "rev-parse", "--verify", "--quiet", "#{ref}^{commit}", chdir: root)
        return if found.success?

        raise ConfigError, "--since #{ref}: not a commit in this repository " \
                           "(check the name; a shallow checkout may need a deeper fetch)"
      end

      def merge_base(ref, root:)
        git(root, "merge-base", ref, "HEAD").strip
      end

      # The file's text at commit BASE, or nil when it did not exist there.
      # path is relative to root.
      def file_at(base, path, root:)
        out, _, status = Open3.capture3("git", "show", "#{base}:./#{path}", chdir: root)
        status.success? ? out.b : nil
      end

      def changed_lines(ref, root:, include: nil, diagnostics: nil)
        verify_ref!(ref, root: root)
        base = merge_base(ref, root: root)
        # Root and paths are filesystem identity: strip as bytes and retag
        # losslessly (strip raises on locale-tagged high bytes; a scrub
        # would rename a raw-byte path). Parse the diff body as bytes and
        # tag each extracted path UTF-8 at the boundary.
        top = Text.utf8_identity(git(root, "rev-parse", "--show-toplevel").b.strip)
        diff = %w[-c core.quotePath=false diff --unified=0 --no-color --no-ext-diff]
        changes = parse(git(root, *diff, base, "--").b, top)
        drop_layout_only_lines(changes, git(root, *diff, "--ignore-space-change", base, "--").b, base, top,
                               include: include)
        UntrackedChanges.union(changes, top, include: include, diagnostics: diagnostics)
        changes
      end

      def parse(diff, top)
        changes = Hash.new { |hash, file| hash[file] = Set.new }
        file = nil
        diff.each_line do |line|
          if line.start_with?("+++ ")
            path = Text.utf8_identity(unquote(line.chomp.delete_prefix("+++ ").delete_suffix("\t")))
            file = path == NO_FILE ? nil : File.join(top, path.delete_prefix("b/"))
          # HUNK is anchored, so a non-hunk line - including a raw-byte
          # content line - fails the match at its first byte.
          elsif file && (match = HUNK.match(line))
            start = match[1].to_i
            count = (match[2] || "1").to_i
            # A pure deletion touches the lines on either side of it.
            lines = count.zero? ? [start, start + 1] : (start...(start + count)).to_a
            changes[file].merge(lines)
          end
        end
        changes.default_proc = nil
        changes
      end

      # Only files the run could mutate are lexed; a file new at the base
      # has nothing to compare with and keeps every line.
      def drop_layout_only_lines(changes, spaced_diff, base, top, include:)
        hunks = spaced_hunks(spaced_diff, top)
        changes.each do |file, lines|
          next unless include.nil? || include.include?(file)

          base_source = file_at(base, file.delete_prefix("#{top}/"), root: top)
          next unless base_source

          current_source = File.binread(file)
          changes[file] = LayoutOnlyLines.new(hunks.fetch(file, []), base_source: base_source,
                                                                     current_source: current_source).restrict(lines)
        end
      end

      # Hunk headers of a zero-context diff, by absolute path of the
      # changed file.
      def spaced_hunks(diff, top)
        file = nil
        diff.each_line.with_object(Hash.new { |hash, key| hash[key] = [] }) do |line, hunks|
          if line.start_with?("+++ ")
            path = Text.utf8_identity(unquote(line.chomp.delete_prefix("+++ ").delete_suffix("\t")))
            file = path == NO_FILE ? nil : File.join(top, path.delete_prefix("b/"))
          elsif file
            LayoutOnlyLines.hunks(line, hunks[file])
          end
        end
      end

      ESCAPES = { "n" => "\n", "t" => "\t", '"' => '"', "\\" => "\\", "a" => "\a", "b" => "\b",
                  "f" => "\f", "r" => "\r", "v" => "\v" }.freeze

      # git C-quotes a path with special bytes: "b/h\303\251llo.rb". It also
      # ends a path that holds a space with a tab, which the caller strips.
      def unquote(path)
        return path unless path.start_with?('"') && path.end_with?('"')

        path[1...-1].gsub(/\\([0-7]{3}|.)/) do
          code = Regexp.last_match(1)
          code.length == 3 ? code.to_i(8).chr : ESCAPES.fetch(code, code)
        end.b.force_encoding(Encoding::UTF_8)
      end

      def git(root, *args)
        out, err, status = Open3.capture3("git", *args, chdir: root)
        raise Error, "git #{args.first} failed: #{err.strip}" unless status.success?

        out
      end
    end
  end
end
