# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  Change = Struct.new(:status, :path, :old_mode, :new_mode, :old_blob, :new_blob, keyword_init: true)

  # Reads identity and the change inventory of the exact base and head commits.
  # Every git call is an argument array, so file names are never parsed as shell text.
  class Repository
    SYMLINK_MODE = "120000"
    SUBMODULE_MODE = "160000"

    attr_reader :merge_base

    def initialize(command_runner:, options:, directory:)
      @git = command_runner
      @options = options
      @git_directory = directory
    end

    def verify_identity!
      verify_commit!(@options.base)
      verify_commit!(@options.head)
      raise UnverifiableInput, "checkout HEAD is #{checkout_head}, not --head" unless checkout_head == @options.head

      @merge_base = capture!(%w[merge-base] + [@options.base, @options.head]).strip
      raise UnverifiableInput, "base has no merge base with head" unless @merge_base.match?(SHA_PATTERN)

      verify_index_flags!
      verify_output_root!
      return if dirty_entries.empty?

      raise UnverifiableInput,
            "working tree is not clean: #{dirty_entries.first(5).join(', ')}"
    end

    # The local origin/main, if the checkout has one. Freshness against GitHub stays unverified.
    def origin_main_snapshot
      result = @git.run(%w[git rev-parse --verify --quiet origin/main^{commit}])
      result.succeeded? ? result.stdout.strip : nil
    end

    def tracked_files
      capture!(%w[ls-files -z]).split("\0")
    end

    def tree_digest
      capture!(%w[rev-parse HEAD^{tree}]).strip
    end

    def checkout_head
      capture!(%w[rev-parse HEAD]).strip
    end

    def dirty_entries
      capture!(%w[status --porcelain=v1 -z --untracked-files=all] + output_exclusion).split("\0")
    end

    def changes
      @changes ||= parse_raw(capture!(%W[diff --raw -z --no-renames --no-abbrev #{@merge_base} #{@options.head}]))
    end

    def blob_at(commit, path)
      result = @git.run(["git", "show", "#{commit}:#{path}"])
      result.succeeded? ? result.stdout : nil
    end

    def commits
      capture!(%W[rev-list --no-merges #{@options.base}..#{@options.head}]).split("\n")
    end

    def capture!(arguments)
      result = @git.run(["git", *arguments])
      raise UnverifiableInput, "git #{arguments.first} failed: #{result.stderr.strip}" unless result.succeeded?

      result.stdout
    end

    private

    # The harness's own report and log directory is not source, so it does not make the tree dirty.
    def output_exclusion
      ["--", ".", ":(exclude)#{OUTPUT_ROOT}"]
    end

    # assume-unchanged and skip-worktree hide edits from git status, so a clean status would mean nothing.
    def verify_index_flags!
      hidden = capture!(%w[ls-files -v -z]).split("\0").select { |entry| entry[0] =~ /[a-z]|S/ }
      return if hidden.empty?

      raise UnverifiableInput, "files marked assume-unchanged or skip-worktree: #{hidden.first(3).map do |e|
        e[2..]
      end.join(', ')}"
    end

    # Reports are written under tmp/preflight. That path must be a real directory inside the checkout,
    # and no tracked file may live there, because status ignores it.
    def verify_output_root!
      root = File.join(@git_directory, OUTPUT_ROOT)
      parent = File.dirname(root)
      [parent, root].each do |path|
        raise UnverifiableInput, "#{path} is a symlink" if File.symlink?(path)
      end
      checkout = File.realpath(@git_directory)
      inside = !File.exist?(root) || File.realpath(root).start_with?("#{checkout}/")
      raise UnverifiableInput, "#{OUTPUT_ROOT} resolves outside the checkout" unless inside
      raise UnverifiableInput, "tracked files exist under #{OUTPUT_ROOT}" unless capture!(["ls-files", "--",
                                                                                           OUTPUT_ROOT]).empty?
    end

    def verify_commit!(sha)
      result = @git.run(["git", "cat-file", "-t", sha])
      return if result.succeeded? && result.stdout.strip == "commit"

      raise UnverifiableInput,
            "commit #{sha} is not available locally"
    end

    def parse_raw(output)
      tokens = output.split("\0")
      changes = []
      until tokens.empty?
        header = tokens.shift
        path = tokens.shift
        raise UnverifiableInput, "malformed diff inventory" unless header&.start_with?(":") && path

        old_mode, new_mode, old_blob, new_blob, status = header.delete_prefix(":").split
        changes << Change.new(status: status, path: path, old_mode: old_mode, new_mode: new_mode,
                              old_blob: old_blob, new_blob: new_blob)
      end
      changes
    end
  end
end
