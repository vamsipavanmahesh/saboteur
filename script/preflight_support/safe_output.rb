# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  # Every write of the harness goes through here. Code from the checkout (a Gemfile, a spec, a tool) runs while the
  # harness has its output directory open, so a path that was checked once can be replaced by a symlink or a FIFO
  # later. Each write therefore re-checks the whole directory chain from the checkout root, and creates the file
  # with O_EXCL | O_NOFOLLOW | O_NONBLOCK: it must be new, it cannot be a link, and a FIFO cannot make it block.
  # Limit: Ruby has no openat, so a directory swapped between the chain check and the open is narrowed, not
  # excluded. The end-of-run tree check (verify_tree!) is what catches a swap that happened in that window.
  module SafeOutput
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
    def verify_tree(dir, root)
      require_chain(dir, root)
      Dir.children(dir).each do |name|
        path = File.join(dir, name)
        stat = File.lstat(path)
        raise ExecutionGap, "#{path} is not a directory or regular file" unless stat.directory? || stat.file?

        verify_tree(path, root) if stat.directory?
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

      path.delete_prefix("#{root}/").split("/")
    end
  end
end
