# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  # Every write of the harness goes through here. Code from the checkout (a Gemfile, a spec, a tool) runs while the
  # harness has its output directory open, so a path that was checked once can be replaced by a symlink or a FIFO
  # later. Each write therefore re-checks the whole directory chain from the checkout root, and creates the file
  # with O_EXCL | O_NOFOLLOW | O_NONBLOCK: it must be new, it cannot be a link, and a FIFO cannot make it block.
  # Limit: Ruby has no openat, so the chain check and the open are two steps. A directory swapped for a link
  # between them is narrowed, not excluded, and a swap that is undone before the end of the run cannot be seen
  # at all. The end-of-run tree check (verify_tree) only catches a bad state that is still there when it runs.
  module SafeOutput
    MAX_DEPTH = 16
    MAX_ENTRIES = 5_000
    MAX_SECONDS = 20
    CREATE = File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW | File::NONBLOCK

    module_function

    # Creates every missing directory below root, one level at a time, and refuses links.
    def make_directories(path, root)
      parts_below(path, root).inject(root) do |current, part|
        current = File.join(current, part)
        begin
          Dir.mkdir(current, 0o700)
        rescue Errno::EEXIST
          nil
        end
        require_directory(current)
        current
      end
    end

    def write_new(path, data, root)
      require_chain(File.dirname(path), root)
      File.open(path, CREATE, 0o600) do |file|
        raise ExecutionGap, "#{path} is not a regular file" unless file.stat.file?

        file.write(data)
      end
    rescue SystemCallError, IOError => e
      raise ExecutionGap, "cannot write #{path} safely: #{e.class}"
    end

    # Every directory on the way down is a real directory, every entry below dir is a directory or a regular file.
    # Iterative and bounded: a tree that is too deep, too large or too slow to walk is an execution gap.
    def verify_tree(dir, root, max_depth: MAX_DEPTH, max_entries: MAX_ENTRIES, max_seconds: MAX_SECONDS)
      require_chain(dir, root)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + max_seconds
      pending = [[dir, 0]]
      entries = 0
      until pending.empty?
        current, depth = pending.pop
        raise ExecutionGap, "#{current} is nested deeper than #{max_depth} levels" if depth > max_depth

        Dir.each_child(current) do |name|
          entries += 1
          raise ExecutionGap, "more than #{max_entries} entries below #{dir}" if entries > max_entries
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            raise ExecutionGap,
                  "walking #{dir} took longer than #{max_seconds}s"
          end

          path = File.join(current, name)
          stat = File.lstat(path)
          raise ExecutionGap, "#{path} is not a directory or regular file" unless stat.directory? || stat.file?

          pending << [path, depth + 1] if stat.directory?
        end
      end
    rescue SystemCallError => e
      raise ExecutionGap, "cannot inspect #{dir}: #{e.class}"
    end

    def require_chain(dir, root)
      parts_below(dir, root).inject(root) do |current, part|
        current = File.join(current, part)
        require_directory(current)
        current
      end
    end

    def require_directory(path)
      stat = File.lstat(path)
      raise ExecutionGap, "#{path} is not a real directory" unless stat.directory?
      raise ExecutionGap, "#{path} is not owned by the current user" unless stat.uid == Process.euid
      raise ExecutionGap, "#{path} is writable by everyone" if stat.mode.anybits?(0o002)
    rescue SystemCallError => e
      raise ExecutionGap, "cannot inspect #{path}: #{e.class}"
    end

    def parts_below(path, root)
      return [] if path == root
      raise ExecutionGap, "#{path} is outside #{root}" unless path.start_with?("#{root}/")

      parts = path.delete_prefix("#{root}/").split("/", -1)
      bad = parts.find { |part| part.empty? || part == "." || part == ".." }
      raise ExecutionGap, "#{path} has an empty, '.' or '..' component" if bad

      parts
    end
  end
end
