# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

module Saboteur
  # The state of the working source a run looked at: the commit it was on and
  # (the full SHA) and whether files differed from it, tracked changes and each
  # untracked file alike.
  # Saboteur's own output (cache and reports) is passed in as ignored paths, so a
  # report from an earlier run does not make the tree look dirty. Without git, or
  # outside a repository, the state is unknown.
  class WorkingTree
    State = Data.define(:head, :dirty, :changed_files) do
      def label
        return "unknown" if dirty.nil?

        dirty ? "dirty" : "clean"
      end

      # Shown before a run: mutants run your code and can change the tree.
      def warning
        return unless dirty

        "saboteur: warning: #{changed_files} uncommitted change(s) in the working tree. " \
          "Mutants run your code and could alter or delete files; run on a clean, committed tree or a CI checkout."
      end
    end

    UNKNOWN = State.new(head: nil, dirty: nil, changed_files: nil)

    # ignored: paths relative to root that are not source (saboteur's cache and reports).
    def initialize(root, ignored: [])
      @root = root
      @ignored = ignored
    end

    def state
      head, head_status = Open3.capture2e("git", "rev-parse", "HEAD", chdir: @root)
      changes, changes_status = Open3.capture2e(*status_command, chdir: @root)
      return UNKNOWN unless head_status.success? && changes_status.success?

      count = changes.lines.size
      State.new(head: head.strip, dirty: count.positive?, changed_files: count)
    rescue SystemCallError
      UNKNOWN
    end

    private

    def status_command
      excluded = @ignored.map { |path| ":(exclude)#{path}" }
      ["git", "status", "--porcelain", "--untracked-files=all", "--", ".", *excluded]
    end
  end
end
