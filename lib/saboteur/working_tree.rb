# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

module Saboteur
  # The state of the working source a run looked at: the commit it was on and
  # whether files differed from it. An agent needs this to know which code a
  # verdict describes. Without git, or outside a repository, the state is unknown.
  class WorkingTree
    State = Data.define(:head, :dirty) do
      def label
        return "unknown" if dirty.nil?

        dirty ? "dirty" : "clean"
      end
    end

    UNKNOWN = State.new(head: nil, dirty: nil)

    def initialize(root)
      @root = root
    end

    def state
      head, head_status = Open3.capture2e("git", "rev-parse", "--short", "HEAD", chdir: @root)
      changes, changes_status = Open3.capture2e("git", "status", "--porcelain", "--untracked-files=no", chdir: @root)
      return UNKNOWN unless head_status.success? && changes_status.success?

      State.new(head: head.strip, dirty: !changes.strip.empty?)
    rescue SystemCallError
      UNKNOWN
    end
  end
end
