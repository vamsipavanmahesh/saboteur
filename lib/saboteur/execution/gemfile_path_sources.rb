# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "open3"

module Saboteur
  module Execution
    # Resolves a Gemfile's path: sources with Bundler's OWN parser in a
    # short-lived child process (#644). Never a line scan: a wrong guess
    # about a path: source silently loads unmutated code in the disposable
    # copy. Fail closed - a Gemfile that cannot be parsed, a resolver that
    # times out, or a path: source outside the project root refuses the
    # run with exit 2 (ConfigError) naming the source.
    # Resolving EVALUATES the project's Gemfile in that child at
    # ExternalRunner.new - arbitrary Ruby with the caller's permissions,
    # the same trust level as the bundle exec in the test command itself.
    module GemfilePathSources
      Source = Data.define(:name, :original, :expanded)

      RESOLVE_TIMEOUT = 15

      # Bundler::Dsl, not Bundler::Definition: the Gemfile must be PARSED by
      # Bundler itself (it is arbitrary Ruby; a line scan can silently miss
      # or invent a path: source and load unmutated code), but resolving the
      # whole bundle is not needed and fails on half-installed projects.
      RESOLVER = <<~RUBY
        dsl = Bundler::Dsl.new
        dsl.eval_gemfile(ENV["BUNDLE_GEMFILE"] || "Gemfile")
        out = dsl.dependencies.filter_map do |dep|
          src = dep.source
          next unless src.is_a?(Bundler::Source::Path)

          { "name" => dep.name, "original" => src.path.to_s, "expanded" => src.expanded_original_path.to_s }
        end
        puts JSON.generate(out)
      RUBY

      module_function

      # Every path: source in the project's Gemfile, resolved by Bundler
      # itself. Raises ConfigError on any failure to parse or resolve.
      # gemfile pins the command's own BUNDLE_GEMFILE (Appraisal style):
      # that file's path: sources are the ones the run loads, so it is
      # the one parsed (#644).
      def resolve(root, env: ENV, timeout: RESOLVE_TIMEOUT, gemfile: nil)
        path = gemfile ? File.expand_path(gemfile, root) : File.join(root, "Gemfile")
        if gemfile && !File.file?(path)
          raise ConfigError, "the test command pins BUNDLE_GEMFILE (#{gemfile}) but #{path} does not exist"
        end

        return [] unless File.file?(path)

        stdout, stderr, status = run_resolver(root, env, timeout, gemfile: path)
        unless status.success?
          detail = stderr.to_s.lines.first(3).join.strip
          detail = "resolver exited #{status.exitstatus}" if detail.empty?
          raise ConfigError, "could not parse the Gemfile's path: sources (#{detail}); " \
                             "external test commands need the Gemfile to resolve"
        end

        JSON.parse(stdout).map do |row|
          Source.new(name: row["name"], original: row["original"], expanded: row["expanded"])
        end
      rescue JSON::ParserError
        raise ConfigError, "could not parse the Gemfile's path: sources (resolver returned unreadable output); " \
                           "external test commands need the Gemfile to resolve"
      end

      # realpath, canonicalizing the deepest EXISTING ancestor when the
      # path itself does not exist yet: behind a symlinked root (macOS
      # /var -> /private/var) a textual expand_path can never match the
      # realpath'd root, so an absolute path: source into the tree read
      # as outside and silently skipped the rebase (#644, #721 macOS).
      def canonical_path(path)
        missing = []
        current = path
        until File.exist?(current)
          missing.unshift(File.basename(current))
          parent = File.dirname(current)
          break if parent == current

          current = parent
        end
        base = File.exist?(current) ? File.realpath(current) : File.expand_path(current)
        File.join(base, *missing)
      rescue SystemCallError
        File.expand_path(path)
      end

      def run_resolver(root, env, timeout, gemfile: nil)
        # Spawn env semantics: a key ABSENT from the hash is inherited, so
        # the bundler anchors must be explicitly unset with nil, or the
        # child resolves saboteur's own Gemfile instead of the project's.
        # Both prefixes: rubygems itself requires ENV["BUNDLER_SETUP"] in
        # gem_prelude, which would resolve the whole bundle at child boot.
        child_env = env.each_key.with_object({}) do |key, memo|
          memo[key] = nil if key.start_with?("BUNDLE_", "BUNDLER_") || key == "RUBYOPT"
        end
        # The Gemfile to parse, re-pinned after the anchor wipe: the
        # command's own BUNDLE_GEMFILE when it sets one (Appraisal style),
        # else the root Gemfile (#644).
        child_env["BUNDLE_GEMFILE"] = gemfile || File.join(root, "Gemfile")
        # Plain ruby, NOT bundle exec: bundle exec resolves the whole bundle
        # before running, which refuses half-installed projects we are only
        # trying to parse (#644). The child leads its own process group so a
        # timeout can KILL the whole group, not only the ruby pid (#644).
        cmd = ["ruby", "-rbundler", "-rjson", "-e", RESOLVER]
        stdin, stdout, stderr, wait = Open3.popen3(child_env, *cmd, chdir: root, pgroup: true)
        stdin.close
        await_resolver(stdout, stderr, wait, timeout)
      ensure
        [stdin, stdout, stderr].each { |io| io&.close unless io&.closed? }
      end

      # Drains both pipes while waiting: a child that fills a pipe buffer
      # (~64 KB) blocks on write and never exits, which would read as a
      # fake timeout (#644). The readers accumulate partial chunks, so a
      # still-open pipe (a spawned grandchild that left the process group
      # holds the write end) can be abandoned after a short grace instead
      # of blocking on EOF - on the timeout path the captured output is
      # discarded, and on a clean exit incomplete output cannot be
      # trusted, so the run refuses either way (#722).
      def await_resolver(stdout, stderr, wait, timeout)
        out_buffer = +""
        err_buffer = +""
        readers = [pipe_reader(stdout, out_buffer), pipe_reader(stderr, err_buffer)]
        timed_out = resolver_timed_out?(wait, timeout)
        readers_done = readers.all? { |reader| reader.join(2) }
        readers.each { |reader| reader.kill if reader.alive? }
        if timed_out
          raise ConfigError, "could not parse the Gemfile's path: sources (resolver timed out after #{timeout} s); " \
                             "external test commands need the Gemfile to resolve"
        end
        unless readers_done
          raise ConfigError, "could not parse the Gemfile's path: sources (a resolver-spawned process still holds " \
                             "its pipes open); external test commands need the Gemfile to resolve"
        end

        [out_buffer, err_buffer, wait.value]
      end

      # true when the resolver missed its deadline and its whole process
      # group was KILLed.
      def resolver_timed_out?(wait, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        until wait.join(0.05)
          next unless Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          Process.kill("KILL", -wait.pid)
          wait.join
          return true
        end
        false
      end

      def pipe_reader(io, buffer)
        Thread.new do
          loop { buffer << io.readpartial(65_536) }
        rescue IOError # EOFError < IOError
          buffer
        end
      end
    end
  end
end
