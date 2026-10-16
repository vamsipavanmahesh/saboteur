# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require_relative "../text"

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
        changes = parse(git(root, "-c", "core.quotePath=false", "diff", "--unified=0", "--no-color",
                            "--no-ext-diff", base, "--").b, top)
        union_untracked(changes, top, include: include, diagnostics: diagnostics)
        changes
      end

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
      # is skipped quietly. Where a platform lacks either flag the union is
      # skipped with a warning rather than done unsafely (the crash log
      # makes the same trade, #296). The binary sniff reads only the first
      # few kilobytes (git's own heuristic window) and the count streams,
      # so a huge untracked source costs one pass, not its content in
      # memory; the map holds a range, not one Set entry per line.
      BINARY_SNIFF_BYTES = 8000
      READ_CHUNK_BYTES = 64 * 1024

      def union_untracked(changes, top, include:, diagnostics:)
        unless File.const_defined?(:NOFOLLOW) && File.const_defined?(:NONBLOCK)
          diagnostics&.warn("--since: untracked files are not included: this platform lacks " \
                            "O_NOFOLLOW/O_NONBLOCK, so they cannot be opened race-free")
          return
        end

        flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
        git(top, "ls-files", "-z", "--others", "--exclude-standard").b.split("\0").each do |name|
          file = File.join(top, Text.utf8_identity(name))
          next if include && !include.include?(CoverageMap.canonical(file))

          lines = untracked_line_count(file, flags)
          changes[file] = (1..lines) if lines
        end
      end

      # Line count of an untracked file opened race-free, or nil when the
      # file stays out of the map: vanished, unreadable, a symlink, not a
      # regular file on the opened descriptor, empty, or binary inside the
      # sniff window.
      def untracked_line_count(file, flags)
        File.open(file, flags) do |io|
          next unless io.stat.file?

          count_lines(io)
        end
      rescue SystemCallError, IOError
        nil
      end

      # Every read is bounded: the binary sniff takes only the first few
      # kilobytes (git's own heuristic window; read of an empty file is nil,
      # never ""), then the count streams in fixed chunks.
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
