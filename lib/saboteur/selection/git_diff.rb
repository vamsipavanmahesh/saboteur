# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require_relative "../text"
require_relative "dependency_shield"
require_relative "layout_only_lines"
require_relative "untracked_changes"

module Saboteur
  module Selection
    # Lines changed between the merge base of REF and HEAD, plus uncommitted
    # changes, as { "/abs/path.rb" => Set[line numbers in the current file] }.
    module GitDiff
      NO_FILE = "/dev/null" # rubocop:disable Style/FileNull -- literal in git diff output
      HUNK = /\A@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/

      LOCAL_BRANCH_CAP = 5
      BASE_NAMES = %w[main master trunk develop].freeze

      module_function

      # Fails before any boot work when REF is not a commit here, as a usage
      # error (exit 2): the name is wrong, or a shallow checkout lacks it.
      def verify_ref!(ref, root:)
        raise ConfigError, "--since needs a git ref, not an option: #{ref}" if ref.start_with?("-")

        _, _, inside = Open3.capture3("git", "rev-parse", "--git-dir", chdir: root)
        raise ConfigError, "--since needs a git repository" unless inside.success?

        _, _, found = Open3.capture3("git", "rev-parse", "--verify", "--quiet", "#{ref}^{commit}", chdir: root)
        return if found.success?

        raise ConfigError, unknown_ref_message(ref, root)
      end

      # The failure moment is where the hint belongs (#595): on a repo whose
      # default branch is not main, a bare `saboteur pr` should say so and
      # name the branch, rather than only hinting at shallow checkouts.
      def unknown_ref_message(ref, root)
        message = "--since #{ref}: not a commit in this repository " \
                  "(check the name; a shallow checkout may need a deeper fetch)"
        branch = default_branch(root)
        return "#{message}#{local_branches_hint(root)}" unless branch

        "#{message}; this repository's default branch is '#{branch}' - " \
          "pass it explicitly: saboteur pr #{branch}"
      end

      # A local-only repo has no origin/HEAD to name: list the branches it
      # does have, so a bare `saboteur pr` (default main) points at a real one.
      def local_branches_hint(root)
        out, _, ok = Open3.capture3("git", "for-each-ref", "--format=%(refname:short)", "refs/heads", chdir: root)
        branches = ok.success? ? likely_bases(out.split("\n")).first(LOCAL_BRANCH_CAP) : []
        return "" if branches.empty?

        "; local branches: #{branches.join(', ')} - pass one explicitly: saboteur pr #{branches.first}"
      end

      # The default branch origin publishes, without the remote name, or nil
      # when origin has no HEAD (a local-only clone keeps the plain hint).
      def default_branch(root)
        out, _, ok = Open3.capture3("git", "symbolic-ref", "refs/remotes/origin/HEAD", "--short", chdir: root)
        return nil unless ok.success?

        branch = out.strip.sub(%r{\A[^/]+/}, "")
        branch.empty? ? nil : branch
      end

      # Conventional base names first, so the suggested example is a base.
      def likely_bases(branches)
        branches.sort_by { |name| [BASE_NAMES.index(name) || BASE_NAMES.size, name] }
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

      # Paths under ROOT, relative to it, that differ between the merge base
      # of REF and the working tree: { present: [...], deleted: [...] }.
      # present holds added, modified and untracked files; deleted holds
      # files gone from the working tree. A rename counts as a deletion of
      # the old path and an addition of the new one.
      def changed_paths(ref, root:)
        verify_ref!(ref, root: root)
        base = merge_base(ref, root: root)
        diff = %w[diff -z --name-only --relative --no-renames]
        {
          # An untracked file is never in the diff, so the two lists are disjoint.
          present: DependencyShield.reject_trees(names(root, *diff, "--diff-filter=d", base, "--") +
                                                 names(root, "ls-files", "-z", "--others",
                                                       "--exclude-standard"), root).sort,
          deleted: DependencyShield.reject_trees(names(root, *diff, "--diff-filter=D", base, "--"),
                                                 root).sort
        }
      end

      def names(root, *args)
        git(root, *args).b.split("\0").map { |name| Text.utf8_identity(name) }
      end

      # The two line maps of a --since diff (#313). changed holds every line
      # the text diff touches: subject admission and the formatting-only
      # skip read it, so a method that was only re-indented is still found
      # and reported as unchanged. behavior drops the layout-only lines:
      # only it narrows a changed method's fine-grained mutants.
      LineMaps = Data.define(:changed, :behavior)

      def changed_lines(ref, root:, include: nil, diagnostics: nil)
        line_maps(ref, root: root, include: include, diagnostics: diagnostics).changed
      end

      # Tracked files whose diff deletes lines without adding any, as
      # canonical absolute paths (realpath'd toplevel joined to each diff
      # path), so callers compare in the same space as
      # CoverageMap.canonical keys whatever the project-root layout: a
      # monorepo root below the git toplevel must not silently disable the
      # exclusion (#484). A pure deletion adds no new code to mutate - the
      # change itself is what the suite covers - so the file yields no
      # subject and no fine-grained mutant, and a spec-less such file must
      # not stop the run. The neighbor lines a pure deletion touches
      # (touched_lines) are context, not change. Untracked files are
      # all-additions and never listed.
      def deletion_only_files(ref, root:) # rubocop:disable Metrics/ModuleLength -- one focused addition to an exactly-full module
        top = File.realpath(Text.utf8_identity(git(root, "rev-parse", "--show-toplevel").b.strip))
        diff = git(root, "-c", "core.quotePath=false", "diff", "--unified=0", "--no-color", "--no-ext-diff",
                   merge_base(ref, root: root), "--").b
        added = Hash.new { |hash, file| hash[file] = false }
        each_hunk(diff, top) { |file, (_, _, _, count)| added[file] ||= count.positive? }
        added.reject { |_, yes| yes }.keys
      end

      def line_maps(ref, root:, include: nil, diagnostics: nil)
        verify_ref!(ref, root: root)
        base = merge_base(ref, root: root)
        # Root and paths are filesystem identity: strip as bytes and retag
        # losslessly (strip raises on locale-tagged high bytes; a scrub
        # would rename a raw-byte path). Parse the diff body as bytes and
        # tag each extracted path UTF-8 at the boundary.
        top = Text.utf8_identity(git(root, "rev-parse", "--show-toplevel").b.strip)
        diff = %w[-c core.quotePath=false diff --unified=0 --no-color --no-ext-diff]
        changes = parse(git(root, *diff, base, "--").b, top)
        UntrackedChanges.union(changes, top, include: include, diagnostics: diagnostics)
        behavior = drop_layout_only_lines(changes, git(root, *diff, "--ignore-space-change", base, "--").b, base,
                                          top, include: include)
        LineMaps.new(changed: changes, behavior: behavior)
      end

      def parse(diff, top)
        changes = Hash.new { |hash, file| hash[file] = Set.new }
        each_hunk(diff, top) { |file, (_, _, start, count)| changes[file].merge(touched_lines(start, count)) }
        changes.default_proc = nil
        changes
      end

      # The new-side lines a hunk touches. A pure deletion touches the lines
      # on either side of it.
      def touched_lines(start, count)
        count.zero? ? [start, start + 1] : (start...(start + count)).to_a
      end

      # Each hunk header of a zero-context diff as the absolute path of the
      # file and [old_start, old_count, new_start, new_count].
      def each_hunk(diff, top)
        file = nil
        diff.each_line do |line|
          if line.start_with?("+++ ")
            path = Text.utf8_identity(unquote(line.chomp.delete_prefix("+++ ").delete_suffix("\t")))
            file = path == NO_FILE ? nil : File.join(top, path.delete_prefix("b/"))
          # HUNK is anchored, so a non-hunk line - including a raw-byte
          # content line - fails the match at its first byte.
          elsif file && (match = HUNK.match(line))
            old_start, old_count, new_start, new_count = match.captures
            yield file, [old_start.to_i, (old_count || "1").to_i, new_start.to_i, (new_count || "1").to_i]
          end
        end
      end

      # Only files the run could mutate are lexed; a file new at the base
      # has nothing to compare with and keeps every line.
      def drop_layout_only_lines(changes, spaced_diff, base, top, include:)
        hunks = Hash.new { |hash, file| hash[file] = [] }
        each_hunk(spaced_diff, top) { |file, hunk| hunks[file] << hunk }
        changes.to_h do |file, lines|
          mutable = include.nil? || include.include?(file)
          base_source = mutable && file_at(base, file.delete_prefix("#{top}/"), root: top)
          next [file, lines] unless base_source

          [file, LayoutOnlyLines.new(hunks[file], base_source: base_source, current_source: File.binread(file))
                                .restrict(lines)]
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
