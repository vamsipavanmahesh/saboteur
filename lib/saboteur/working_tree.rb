# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require_relative "text"

module Saboteur
  # The state of the working source a run looked at: the commit it was on and
  # (the full SHA) and whether files differed from it, tracked changes and each
  # untracked file alike.
  # Saboteur's own output (cache and reports) is passed in as ignored paths, so a
  # report from an earlier run does not make the tree look dirty. Without git, or
  # outside a repository, the state is unknown.
  class WorkingTree
    # One uncommitted change: its path relative to the root (the new path
    # of a rename, the old path of a deletion) and whether git tracks it.
    Change = Data.define(:path, :tracked)

    State = Data.define(:head, :dirty, :changed_files, :changes) do
      def initialize(head:, dirty:, changed_files:, changes: [])
        super
      end

      def label
        return "unknown" if dirty.nil?

        dirty ? "dirty" : "clean"
      end
    end

    UNKNOWN = State.new(head: nil, dirty: nil, changed_files: nil)
    UNTRACKED = "??"
    RENAMED_OR_COPIED = /[RC]/

    # ignored: paths relative to root that are not source (saboteur's cache and reports).
    def initialize(root, ignored: [])
      @root = root
      @ignored = ignored
    end

    # git status names paths from the top of the repository; the prefix
    # turns them into paths relative to the root.
    def state
      head, _, head_status = Open3.capture3("git", "rev-parse", "HEAD", "--show-prefix", chdir: @root)
      status, _, status_status = Open3.capture3(*status_command, chdir: @root)
      return UNKNOWN unless head_status.success? && status_status.success?

      sha, prefix = head.lines.map(&:chomp)
      changes = changes_in(status, Text.utf8_identity(prefix.to_s))
      State.new(head: sha, dirty: changes.any?, changed_files: changes.size, changes: changes)
    rescue SystemCallError
      UNKNOWN
    end

    private

    # Porcelain v1 with -z: "XY path" entries separated by NUL, a rename or
    # copy followed by one more entry holding its old path.
    def changes_in(status, prefix)
      entries = status.b.split("\0")
      changes = []
      until entries.empty?
        entry = entries.shift
        code = entry[0, 2]
        entries.shift if code.match?(RENAMED_OR_COPIED)
        path = Text.utf8_identity(entry[3..]).delete_prefix(prefix)
        changes << Change.new(path: path, tracked: code != UNTRACKED)
      end
      changes
    end

    def status_command
      excluded = @ignored.map { |path| ":(exclude)#{path}" }
      ["git", "status", "--porcelain", "-z", "--untracked-files=all", "--", ".", *excluded]
    end
  end
end
