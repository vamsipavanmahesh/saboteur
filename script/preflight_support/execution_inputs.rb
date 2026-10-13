# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "json"

module Preflight
  # Identity of what the checks run on, compared before and after the run. It covers:
  #  - the content of every tracked file as it is on disk (not only the committed tree)
  #  - ignored files that change execution (Gemfile.lock, .bundle/config, .rspec-local, ...)
  #  - the Ruby and Bundler versions and a fixed list of environment variables
  # Values are digests, never contents, so Bundler credentials never reach a report.
  # It does not cover every ambient input: other environment variables, the network, the clock, other
  # installed gems not pinned by the lockfile. A required input that exists but cannot be read stops the run.
  class ExecutionInputs
    IGNORED_FILES = %w[Gemfile.lock .bundle/config .rspec-local .rubocop-local.yml].freeze
    RELEVANT_ENV = %w[BUNDLE_APP_CONFIG BUNDLE_USER_CONFIG BUNDLE_GEMFILE RUBYOPT RUBYLIB RSPEC_OPTS RUBOCOP_OPTS CI
                      LANG LC_ALL TZ].freeze

    def initialize(repository:, directory:, command_runner:, env: ENV)
      @repository = repository
      @directory = directory
      @runner = command_runner
      @env = env
    end

    # Passive identity: reads files and runs git only. Nothing from the candidate checkout is executed.
    def digest
      Digest::SHA256.hexdigest(JSON.generate(snapshot))
    end

    def snapshot
      { tree: @repository.tree_digest, tracked_files: tracked_digest, ignored_files: ignored_digests,
        environment: environment_digests, ruby: RUBY_DESCRIPTION, rubygems: Gem::VERSION,
        tools: tool_identities, bundler_files: bundler_files }
    end

    def digest_of(snapshot)
      Digest::SHA256.hexdigest(JSON.generate(snapshot))
    end

    # The fingerprint after dependency preparation. The only difference allowed from the one before it is a
    # lockfile that did not exist and now does (Bundler writes it in a fresh checkout). Anything else is a gap.
    def baseline(before, after)
      raise ExecutionGap, "inputs changed while dependencies were prepared" unless same_but_new_lockfile?(before, after)

      digest_of(after)
    end

    # Dependency identity: runs Bundler, which evaluates the candidate's Gemfile. The runner calls this only
    # after the protected-path checks passed. It records gem names and versions, not their source contents.
    def dependency_digest
      prepare_lockfile
      Digest::SHA256.hexdigest(JSON.generate(bundler: bundler_version, bundled_gems: bundled_gems))
    end

    private

    # In a fresh checkout there is no lockfile and the first Bundler command that resolves would create it in the
    # middle of the run. Create it here, from locally installed gems only (no network), so the run starts stable.
    def prepare_lockfile
      return unless bundler_files[:lockfile].last == "absent"

      result = @runner.run(%w[bundle lock --local], timeout: 120)
      return if result.succeeded?

      raise ExecutionGap, "cannot prepare the lockfile: #{result.problem || result.stderr.strip}"
    end

    def same_but_new_lockfile?(before, after)
      JSON.generate(without_new_lockfile(before, after)) == JSON.generate(before)
    end

    def without_new_lockfile(before, after)
      shaped = JSON.parse(JSON.generate(after))
      original = JSON.parse(JSON.generate(before))
      if absent?(original["ignored_files"]["Gemfile.lock"])
        shaped["ignored_files"]["Gemfile.lock"] =
          original["ignored_files"]["Gemfile.lock"]
      end
      lock = original["bundler_files"]["lockfile"]
      if lock.last == "absent" && shaped["bundler_files"]["lockfile"].first == lock.first
        shaped["bundler_files"]["lockfile"] =
          lock
      end
      shaped
    end

    def absent?(state)
      state == "absent"
    end

    def tracked_digest
      entries = @repository.tracked_files.map { |path| [path, file_state(path, required: true)] }
      Digest::SHA256.hexdigest(JSON.generate(entries))
    end

    def ignored_digests
      IGNORED_FILES.to_h { |name| [name, file_state(name, required: false)] }
    end

    # "absent" only for a path that does not exist. A directory, a broken symlink or an unreadable
    # file where a file is expected is an error, never "absent".
    def file_state(path, required:)
      full = File.join(@directory, path)
      stat = File.lstat(full)
      return symlink_state(full, path, required) if stat.symlink?
      return StrictJson.digest(full) if stat.file?
      raise ExecutionGap, "#{path} is a directory or submodule, which preflight does not support" if stat.directory?

      raise ExecutionGap, "#{path} exists but is not a readable regular file"
    rescue Errno::ENOENT
      required ? "missing" : "absent"
    rescue SystemCallError => e
      raise ExecutionGap, "#{path} cannot be read: #{e.class}"
    end

    # A symlink is identified by its target text and by the content it resolves to. A link that leaves the
    # checkout or does not lead to a regular file is unsupported, because its bytes could change unseen.
    def symlink_state(full, path, _required)
      resolved = File.realpath(full)
      root = File.realpath(@directory)
      raise ExecutionGap, "#{path} is a symlink that leaves the checkout" unless resolved.start_with?("#{root}/")
      raise ExecutionGap, "#{path} is a symlink that does not lead to a regular file" unless File.file?(resolved)

      "symlink:#{File.readlink(full)}:#{StrictJson.digest(resolved)}"
    rescue Errno::ENOENT, Errno::ELOOP
      raise ExecutionGap, "#{path} is a broken symlink"
    end

    # The tools that actually run, found through PATH, by content digest.
    def tool_identities
      %w[ruby bundle].to_h { |name| [name, tool_digest(name)] }
    end

    # Resolved the way the OS does it: first PATH entry holding a readable executable regular file. An empty
    # or relative PATH entry depends on the working directory, so it is refused.
    def tool_digest(name)
      @env.fetch("PATH", "").split(File::PATH_SEPARATOR, -1).each do |dir|
        raise ExecutionGap, "PATH has an empty or relative entry #{dir.inspect}" unless dir.start_with?("/")

        candidate = File.join(dir, name)
        return "#{File.realpath(candidate)}:#{StrictJson.digest(candidate)}" if runnable?(candidate)
      end
      raise ExecutionGap, "#{name} was not found on PATH"
    rescue SystemCallError => e
      raise ExecutionGap, "#{name} cannot be read: #{e.class}"
    end

    def runnable?(path)
      File.file?(path) && File.executable?(path) && File.readable?(path)
    end

    # The resolved gem set. Bundler credentials are never printed; only digests of its settings files.
    def bundled_gems
      result = @runner.run(%w[bundle list], timeout: 120)
      raise ExecutionGap, "cannot list the bundle: #{result.problem || result.stderr.strip}" unless result.succeeded?

      Digest::SHA256.hexdigest(result.stdout)
    end

    # Effective Bundler files: the Gemfile (BUNDLE_GEMFILE, relative to the checkout) and its lockfile, the app
    # and user config. Absent means the path does not exist; anything else unreadable stops the run. Only digests
    # are kept. Settings that Bundler takes from other BUNDLE_* variables are covered only by the environment list.
    def bundler_files
      gemfile = File.expand_path(@env.fetch("BUNDLE_GEMFILE", "Gemfile"), @directory)
      lock = lockfile_for(gemfile)
      app_config = File.join(File.expand_path(@env.fetch("BUNDLE_APP_CONFIG", ".bundle"), @directory), "config")
      user_config = @env.fetch("BUNDLE_USER_CONFIG", File.join(Dir.home, ".bundle", "config"))
      { gemfile: gemfile, lockfile: lock, app_config: app_config, user_config: user_config }
        .transform_values { |path| [path, absolute_state(path)] }
    end

    # Bundler's own rule (checked against Bundler.default_lockfile): gems.rb uses gems.locked next to it;
    # every other name, including Gemfile and custom names, gets ".lock" appended.
    def lockfile_for(gemfile)
      return File.join(File.dirname(gemfile), "gems.locked") if File.basename(gemfile) == "gems.rb"

      "#{gemfile}.lock"
    end

    def absolute_state(path)
      stat = File.lstat(path)
      raise ExecutionGap, "#{path} is not a regular file or a link to one" unless stat.file? || stat.symlink?

      File.file?(path) ? StrictJson.digest(path) : raise(ExecutionGap, "#{path} is a broken symlink")
    rescue Errno::ENOENT
      "absent"
    rescue SystemCallError => e
      raise ExecutionGap, "#{path} cannot be read: #{e.class}"
    end

    def environment_digests
      RELEVANT_ENV.to_h { |name| [name, @env[name] ? Digest::SHA256.hexdigest(@env[name]) : "unset"] }
    end

    def bundler_version
      result = @runner.run(%w[bundle --version], timeout: 60)
      unless result.succeeded?
        raise ExecutionGap,
              "cannot determine the Bundler version: #{result.problem || result.stderr.strip}"
      end

      result.stdout.strip
    end
  end
end
