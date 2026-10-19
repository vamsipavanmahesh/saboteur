# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../text"

module Saboteur
  module Selection
    # Untracked files as changed-line coverage for --since.
    #
    # A diff cannot see untracked files, so a never-committed source file
    # would silently contribute no changed lines - and, being in no map,
    # not even the changed-files-without-subjects warning (#295). Union
    # every untracked file that could hold subjects (the include set the
    # run will mutate) as fully changed: a new file is the strongest
    # possible "changed since ref" signal. Ignored files stay invisible
    # (--exclude-standard), and binary or empty files carry no lines,
    # matching how a committed binary diffs to no hunks.
    #
    # Each file is opened RDONLY|NOFOLLOW|NONBLOCK and validated on that
    # one descriptor, closing the listing-to-read race: a symlink swapped
    # in after the listing fails the open, a FIFO opens without blocking
    # and fails the regular-file stat, and a vanished or unreadable file
    # is reported. Where a platform lacks either flag the union is skipped
    # with a warning rather than done unsafely (the crash log makes the
    # same trade, #296). The binary sniff reads only the first few
    # kilobytes (git's own heuristic window) and the count streams, so a
    # huge untracked source costs one pass, not its content in memory; the
    # map holds a range, not one Set entry per line.
    module UntrackedChanges
      BINARY_SNIFF_BYTES = 8000
      READ_CHUNK_BYTES = 64 * 1024

      module_function

      # Add every include-eligible untracked file to CHANGES as a full
      # range. Eligible files that cannot be read are warned about and
      # recorded as discovery failures, not dropped silently, so the run is
      # reported incomplete instead of clean over mixed source.
      def union(changes, top, include:, diagnostics:)
        unless File.const_defined?(:NOFOLLOW) && File.const_defined?(:NONBLOCK)
          diagnostics&.warn("--since: untracked files are not included: this platform lacks " \
                            "O_NOFOLLOW/O_NONBLOCK, so they cannot be opened race-free")
          return
        end

        flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
        unreadable = []
        files(top).each do |name|
          file = File.join(top, name)
          # Membership is lexical first: an included path swapped to a
          # symlink must reach the safe open, which rejects it, so the swap
          # is reported instead of filtered out on the resolved target. The
          # canonical fallback keeps a symlinked ROOT in scope, because the
          # include set is realpath'd.
          next if include && !include.include?(file) && !include.include?(CoverageMap.canonical(file))

          case (lines = line_count(file, flags))
          when :unreadable then unreadable << name
          when Integer then changes[file] = (1..lines)
          end
        end
        unreadable.each do |name|
          diagnostics&.record_discovery_failure(File.join(top, name), reason: "unreadable")
        end
        warn_unreadable(unreadable, diagnostics)
      end

      # Absolute paths of untracked, non-ignored files under ROOT: they
      # never appear in the diff but can still sit in excluded territory.
      def paths(root)
        top = Text.utf8_identity(GitDiff.git(root, "rev-parse", "--show-toplevel").b.strip)
        files(top).map { |name| File.join(top, name) }
      end

      def files(top)
        GitDiff.git(top, "ls-files", "-z", "--others", "--exclude-standard").b.split("\0").map do |name|
          Text.utf8_identity(name)
        end
      end

      # An included untracked file that cannot be read (vanished,
      # unreadable or replaced after the listing) is missing source
      # coverage: a clean --since must not hide it.
      def warn_unreadable(names, diagnostics)
        return if names.empty? || diagnostics.nil?

        shown = Text.name_list(names.sort)
        diagnostics.warn("--since: #{names.size} included untracked file(s) could not be read (vanished, " \
                         "unreadable or replaced), so their subjects are not covered: #{shown}")
      end

      # Line count of an untracked file opened race-free: nil when the
      # file stays out of the map by content (empty, or binary inside the
      # sniff window), or :unreadable when it could not be validated
      # (vanished, unreadable, a symlink, not a regular file).
      def line_count(file, flags)
        File.open(file, flags) do |io|
          next :unreadable unless io.stat.file?

          count_lines(io)
        end
      rescue SystemCallError, IOError
        :unreadable
      end

      # Every read is bounded: the binary sniff takes only the first few
      # kilobytes (git's own heuristic window; read of an empty file is
      # nil, never ""), then the count streams in fixed chunks.
      def count_lines(io)
        first = io.read(BINARY_SNIFF_BYTES)
        return if first.nil? || first.include?("\0")

        lines = first.count("\n")
        trailing_newline = first.end_with?("\n")
        # A no-arg read returns "" at EOF, never nil - guard the loop so a
        # mutant that drops the chunk size spins zero times, not forever.
        while (chunk = io.read(READ_CHUNK_BYTES)) && !chunk.empty?
          lines += chunk.count("\n")
          trailing_newline = chunk.end_with?("\n")
        end
        trailing_newline ? lines : lines + 1
      end
    end
  end
end
