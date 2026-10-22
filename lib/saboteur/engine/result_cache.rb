# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require_relative "../text"

module Saboteur
  class Engine
    # Opt-in reuse of earlier verdicts (--incremental), like PIT's and
    # Stryker's history files.
    #
    # A verdict is reused only while everything it was computed from is the
    # same: the method's source, the whole file the method lives in (so a
    # constant or helper changed elsewhere in that file is seen), the mutant,
    # the set of covering tests, the content of those tests' files, the
    # lockfile, the run's inputs (config, the saboteur version, the Ruby
    # runtime's engine, version, patchlevel and platform), and every source
    # file a covering test touched (a method it calls, a constant defined
    # elsewhere - #197). Only killed, survived and timeout are stored;
    # errors and skips always run again.
    #
    # When the dependency set is unknown - no coverage map, or an empty one -
    # every source file is watched instead: reuse turns conservative, never
    # stale.
    class ResultCache
      # 2: entries carry value_differed (#1290); a version 1 file is dropped so
      # no cached survivor reads as "never differed" without having been observed.
      FORMAT = 2
      MAX_BYTES = 64 * 1024 * 1024
      STORED = %i[killed survived timeout].freeze
      LOCKFILES = %w[Gemfile.lock gems.locked].freeze
      # Dependency declarations themselves, so the no-lockfile library
      # shape (bundler's own convention: libraries gitignore the lockfile)
      # still invalidates on a dependency edit (#408).
      MANIFESTS = %w[Gemfile gems.rb].freeze

      SOURCE_EXCLUDES = %w[.git vendor node_modules].freeze

      # Seconds between checkpoint saves while verdicts arrive, so a run
      # killed mid-phase (OOM, CI timeout, SIGKILL) keeps what it finished
      # (#471).
      SAVE_INTERVAL = 30

      # suite_digest: SuiteFiles#digest, so an edit to a spec helper or
      # support file invalidates every verdict.
      def initialize(path:, root:, inputs:, suite_digest: "", coverage: nil, fallback_files: [],
                     save_interval: SAVE_INTERVAL, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @path = path
        @root = root
        @inputs = inputs
        @suite_digest = suite_digest
        # Engine always passes the built map; a missing one behaves as an
        # empty one, which watches every fallback and child-loaded source (#197).
        @coverage = coverage || Selection::CoverageMap.new(lines: {}, tests: [])
        @fallback_files = fallback_files.map { |file| File.expand_path(file, root) }.sort
        @entries = load
        @file_digests = {}
        @save_interval = save_interval
        @clock = clock
        @last_saved = clock.call
      end

      # The stored verdict as a hash (status, reason, killed_by, kill_cause,
      # runtime, value_differed), or nil when it may no longer hold.
      def lookup(subject, mutation, tests)
        entry = @entries[key(subject, mutation)]
        return nil unless entry && entry["fingerprint"] == fingerprint(subject, tests)

        { status: entry["status"].to_sym, reason: entry["reason"], killed_by: entry["killed_by"],
          kill_cause: entry["kill_cause"], runtime: entry["runtime"], value_differed: entry["value_differed"] }
      end

      def record(result)
        return unless STORED.include?(result.status)

        @entries[key(result.subject, result.mutation)] = {
          "fingerprint" => fingerprint(result.subject, result.covered_by), "status" => result.status.to_s,
          "reason" => result.reason, "killed_by" => result.killed_by, "kill_cause" => result.kill_cause,
          "runtime" => result.runtime, "value_differed" => result.value_differed
        }
        checkpoint if @clock.call - @last_saved >= @save_interval
      end

      # Written to a temp file and renamed, so a kill mid-write leaves the
      # previous complete file, never a truncated one. A failed write or
      # rename removes the temp file and raises.
      def save
        FileUtils.mkdir_p(File.dirname(@path))
        temp = "#{@path}.#{SecureRandom.hex(8)}.tmp"
        begin
          # "wx": a planted file or symlink at the temp name is never followed.
          File.open(temp, "wx", 0o600) { |out| out.write(JSON.generate(format: FORMAT, entries: @entries)) }
          File.rename(temp, @path)
        rescue StandardError
          FileUtils.rm_f(temp)
          raise
        end
        @last_saved = @clock.call
      end

      private

      # A mid-run save is a safety net, so it is best effort: a full disk or
      # an unwritable directory must not abort a run that is still producing
      # verdicts. The wait restarts either way, so a broken disk is tried
      # once per interval, not once per verdict. The final save is not
      # swallowed (Engine calls #save).
      def checkpoint
        save
      rescue SystemCallError
        @last_saved = @clock.call
      end

      # The current project source files, relative and sorted. A file added
      # after the map was built changes the set and invalidates every stored
      # verdict, whether or not any watched file references it yet.
      def source_set
        @source_set ||= Dir.glob("**/*.rb", base: @root)
                           .reject { |rel| SOURCE_EXCLUDES.include?(rel.split("/").first) }
                           .sort
                           .join("\0")
      end

      # The file is untrusted input (a restored cache, a --resume directory):
      # read only as a regular file, never a symlink or FIFO, under a size
      # cap, and kept only when entries is a Hash of Hashes.
      def load
        return {} unless File.lstat(@path).file?

        text = slurp
        return {} unless text

        data = JSON.parse(Text.utf8_strict(text))
        entries = data["entries"] if data.is_a?(Hash) && data["format"] == FORMAT
        well_formed?(entries) ? entries : {}
      rescue SystemCallError, JSON::ParserError, ArgumentError, EncodingError
        {}
      end

      def slurp
        File.open(@path, File::RDONLY | File::NONBLOCK | File::NOFOLLOW) do |io|
          text = io.read(MAX_BYTES)
          text if io.eof?
        end
      end

      def well_formed?(entries)
        entries.is_a?(Hash) && entries.values.all? { |entry| entry.is_a?(Hash) && typed?(entry) }
      end

      # The fields the reports read, typed so a crafted entry cannot crash
      # them.
      def typed?(entry)
        STORED.map(&:to_s).include?(entry["status"]) && (entry["runtime"].nil? || entry["runtime"].is_a?(Numeric)) &&
          %w[reason kill_cause].all? { |key| entry[key].nil? || entry[key].is_a?(String) } &&
          entry["killed_by"].is_a?(Array) && entry["killed_by"].all?(String) &&
          [nil, true, false].include?(entry["value_differed"])
      end

      def key(subject, mutation)
        "#{subject.id} #{mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)}"
      end

      def fingerprint(subject, tests)
        digest = Digest::SHA256.new
        digest << [VERSION, RUBY_ENGINE, RUBY_VERSION, RUBY_PATCHLEVEL, RUBY_PLATFORM, @inputs, @suite_digest,
                   source_set, subject.source].join("\0") << "\0"
        # A hex digest has a fixed width, so it needs no separator after it.
        digest << Digest::SHA256.hexdigest(subject.file_source)
        digest_tests(digest, tests)
        hash_dependency_inputs(digest)
        digest.hexdigest
      end

      def digest_tests(digest, tests)
        tests.sort.each { |test| digest << test << "\0" << file_digest(test_file(test)) << "\0" }
        dependencies(tests).each { |dep| digest << dep << "\0" << file_digest(dep) << "\0" }
        LOCKFILES.each { |name| digest << file_digest(File.join(@root, name)) << "\0" }
      end

      # Files a change in which can flip the verdict (#197): every source
      # file a covering test touched, from the run's coverage map, plus the
      # loaded sources the map never observed (#344, #353).
      def dependencies(tests)
        (@coverage.files_for(tests) | @coverage.boot_files | unobserved_files).sort
      end

      # Loaded sources the map never observed (no line, method, or load
      # evidence): coverage cannot say whether they matter, so a change in
      # any of them must invalidate (#344).
      def unobserved_files
        @unobserved_files ||=
          (@fallback_files | @coverage.loaded_files).select { |file| @coverage.empty_for?([file]) }
      end

      # RSpec ids name their file: "./spec/a_spec.rb[1:2]".
      def test_file(test)
        File.expand_path(test[/\A(.+?\.rb)(?:\[|:|\z)/, 1] || test, @root)
      end

      def hash_dependency_inputs(digest)
        dependency_files.each { |path| digest << path.delete_prefix("#{@root}/") << "\0" << file_digest(path) << "\0" }
      end

      # Manifests and gemspecs anywhere below the root, since a monorepo
      # sub-gem carries its own dependency declarations (#561); keyed
      # root-relative so same-named sub-gem files cannot collide. Vendored
      # installs and dependencies' own checkouts hold gemspecs the project
      # does not declare, so the scan mirrors RunFingerprint's exclusions.
      def dependency_files
        @dependency_files ||= Dir[File.join(@root, "**", "{#{MANIFESTS.join(',')},*.gemspec}")].reject do |path|
          path.delete_prefix("#{@root}/").split("/").any? { |part| RunFingerprint::EXCLUDED_DIRECTORIES.include?(part) }
        end
      end

      def file_digest(path)
        @file_digests[path] ||= File.file?(path) ? Digest::SHA256.file(path).hexdigest : "missing"
      end
    end
  end
end
