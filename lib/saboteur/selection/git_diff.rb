# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

module Saboteur
  module Selection
    # Lines changed between the merge base of REF and HEAD, plus uncommitted
    # changes, as { "/abs/path.rb" => Set[line numbers in the current file] }.
    module GitDiff
      NO_FILE = "/dev/null" # rubocop:disable Style/FileNull -- literal in git diff output
      HUNK = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

      module_function

      def changed_lines(ref, root:)
        base = git(root, "merge-base", ref, "HEAD").strip
        top = git(root, "rev-parse", "--show-toplevel").strip
        parse(git(root, "diff", "--unified=0", "--no-color", "--no-ext-diff", base, "--"), top)
      end

      def parse(diff, top)
        changes = Hash.new { |hash, file| hash[file] = Set.new }
        file = nil
        diff.each_line do |line|
          if line.start_with?("+++ ")
            path = line.chomp.delete_prefix("+++ ")
            file = path == NO_FILE ? nil : File.join(top, path.delete_prefix("b/"))
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

      def git(root, *args)
        out, err, status = Open3.capture3("git", *args, chdir: root)
        raise Error, "git #{args.first} failed: #{err.strip}" unless status.success?

        out
      end
    end
  end
end
