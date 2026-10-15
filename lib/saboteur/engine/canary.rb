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
        # Retag losslessly: path bytes are identity here, and later
        # File.join calls must not mix encodings.
        @root = Text.utf8_identity(root.to_s)
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
        raise Saboteur::CanaryTripped, message(missing, culprit)
      end

      # The cheap per-mutant probe (#235): stats the snapshot paths only -
      # no git, no glob - so it can run after every mutant.
      def probe
        @snapshot.reject { |rel| present?(rel) }
      end

      # Like check!, but for the per-mutant probe: the mutant whose run just
      # ended is named, never the subject's most recent mutant.
      def probe!(subject: nil, digest: nil)
        missing = probe
        return if missing.empty?

        of = " of #{subject.id}" if subject
        culprit = digest ? " The mutant that just ran, #{digest}#{of}, is the likely cause." : ""
        raise Saboteur::CanaryTripped.new(message(missing, culprit), culprit_digest: digest)
      end

      private

      def present?(rel)
        File.exist?(File.join(@root, rel)) || File.symlink?(File.join(@root, rel))
      end

      def message(missing, culprit)
        "canary: #{missing.size} watched file(s) vanished from the working tree while mutants ran " \
          "(first: #{Text.utf8(missing.first)}).#{culprit} The canary watches tracked files and .git presence " \
          "and only detects the loss after the fact; it cannot restore anything. Recover from your " \
          "own backup, a fresh checkout, or a reclone - a deleted .git or uncommitted work is gone " \
          "unless you have another copy."
      end

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
        # only paths present in the worktree so a deletion shows up. Split
        # the raw bytes first and retag each path losslessly: scrubbing a
        # raw-byte name would make the File.exist? probe fail and drop the
        # file from the watch, so its deletion would go unseen.
        out.b.split("\0".b).map { |rel| Text.utf8_identity(rel) }
           .reject { |rel| cache_path?(rel) }
           .select { |rel| File.exist?(File.join(@root, rel)) || File.symlink?(File.join(@root, rel)) }
      end

      def walk_files
        Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH)
           .select { |path| File.file?(path) }
           .map { |path| Text.utf8_identity(path).delete_prefix("#{@root}/") }
           .reject { |rel| rel.start_with?("#{GIT_DIR}/") || cache_path?(rel) }
      end

      def cache_path?(rel)
        rel.start_with?("#{@cache_dir}/")
      end
    end
  end
end
