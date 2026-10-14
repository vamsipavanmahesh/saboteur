# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require_relative "../text"

module Saboteur
  class Engine
    # Watches the working tree while mutants run (issue #102). A mutant that
    # slips past the hazard guard and deletes tracked files must abort the
    # run, not be reported as a survivor. The snapshot is the tracked files
    # (git ls-files) when the tree is a repository, else every file under the
    # root; the tool's own cache directory is excluded in both cases, and the
    # presence of .git is watched separately.
    class Canary
      GIT_DIR = ".git"

      def initialize(root, cache_dir: ".saboteur")
        @root = root
        @cache_dir = cache_dir.to_s
        @snapshot = inventory
      end

      # After a subject's mutants: any file present at snapshot time and gone
      # now means a mutant deleted it. digest names the most recent mutant,
      # the likely cause.
      def check!(subject: nil, digest: nil)
        missing = @snapshot - inventory
        return if missing.empty?

        of = " of #{subject.id}" if subject
        culprit = digest ? " The most recent mutant, #{digest}#{of}, is the likely cause." : ""
        raise Saboteur::CanaryTripped,
              "canary: #{missing.size} watched file(s) vanished from the working tree while mutants ran " \
              "(first: #{missing.first}).#{culprit} The canary watches tracked files and .git presence " \
              "and only detects the loss after the fact; it cannot restore anything. Recover from your " \
              "own backup, a fresh checkout, or a reclone - a deleted .git or uncommitted work is gone " \
              "unless you have another copy."
      end

      private

      def inventory
        files = git? ? git_tracked_files : walk_files
        files << GIT_DIR if File.exist?(File.join(@root, GIT_DIR))
        files.uniq
      end

      def git?
        File.directory?(File.join(@root, GIT_DIR)) && system("git", "--version", %i[out err] => File::NULL)
      end

      def git_tracked_files
        out, status = Open3.capture2("git", "ls-files", "-z", chdir: @root)
        return walk_files unless status.success?

        # ls-files reads the index, which still names a deleted file; keep
        # only paths present in the worktree so a deletion shows up.
        Text.utf8(out).split("\0").reject { |rel| cache_path?(rel) }
            .select { |rel| File.exist?(File.join(@root, rel)) || File.symlink?(File.join(@root, rel)) }
      end

      def walk_files
        Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH)
           .select { |path| File.file?(path) }
           .map { |path| path.delete_prefix("#{@root}/") }
           .reject { |rel| rel.start_with?("#{GIT_DIR}/") || cache_path?(rel) }
      end

      def cache_path?(rel)
        rel.start_with?("#{@cache_dir}/")
      end
    end
  end
end
