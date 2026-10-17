# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
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
    # lockfile, the run's inputs (config, saboteur version), and every source
    # file a covering test touched (a method it calls, a constant defined
    # elsewhere - #197). Only killed, survived and timeout are stored;
    # errors and skips always run again.
    #
    # When the dependency set is unknown - no coverage map, or an empty one -
    # every source file is watched instead: reuse turns conservative, never
    # stale.
    class ResultCache
      FORMAT = 1
      STORED = %i[killed survived timeout].freeze
      LOCKFILES = %w[Gemfile.lock gems.locked].freeze

      # suite_digest: SuiteFiles#digest, so an edit to a spec helper or
      # support file invalidates every verdict.
      def initialize(path:, root:, inputs:, suite_digest: "", coverage: nil, fallback_files: [])
        @path = path
        @root = root
        @inputs = inputs
        @suite_digest = suite_digest
        @coverage = coverage
        @fallback_files = fallback_files.map { |file| File.expand_path(file, root) }.sort
        @entries = load
        @file_digests = {}
      end

      # The stored verdict as a hash (status, reason, killed_by, kill_cause,
      # runtime), or nil when it may no longer hold.
      def lookup(subject, mutation, tests)
        entry = @entries[key(subject, mutation)]
        return nil unless entry && entry["fingerprint"] == fingerprint(subject, tests)

        { status: entry["status"].to_sym, reason: entry["reason"], killed_by: entry["killed_by"],
          kill_cause: entry["kill_cause"], runtime: entry["runtime"] }
      end

      def record(result)
        return unless STORED.include?(result.status)

        @entries[key(result.subject, result.mutation)] = {
          "fingerprint" => fingerprint(result.subject, result.covered_by), "status" => result.status.to_s,
          "reason" => result.reason, "killed_by" => result.killed_by, "kill_cause" => result.kill_cause,
          "runtime" => result.runtime
        }
      end

      def save
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.generate(format: FORMAT, entries: @entries))
      end

      private

      def load
        data = JSON.parse(Text.utf8_strict(File.read(@path)))
        data["format"] == FORMAT ? data["entries"] : {}
      rescue SystemCallError, JSON::ParserError
        {}
      end

      def key(subject, mutation)
        "#{subject.id} #{mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)}"
      end

      def fingerprint(subject, tests)
        digest = Digest::SHA256.new
        digest << VERSION << "\0" << @inputs << "\0" << @suite_digest << "\0" << subject.source << "\0"
        # A hex digest has a fixed width, so it needs no separator after it.
        digest << Digest::SHA256.hexdigest(subject.file_source)
        digest_tests(digest, tests)
        digest.hexdigest
      end

      def digest_tests(digest, tests)
        tests.sort.each { |test| digest << test << "\0" << file_digest(test_file(test)) << "\0" }
        dependencies(tests).each { |dep| digest << dep << "\0" << file_digest(dep) << "\0" }
        LOCKFILES.each { |name| digest << file_digest(File.join(@root, name)) << "\0" }
      end

      # Files a change in which can flip the verdict (#197): every source
      # file a covering test touched, from the run's coverage map. Without a
      # usable map the dependency set is unknown, so every source file is
      # watched - the conservative whole-project key.
      def dependencies(tests)
        return @fallback_files if @coverage.nil? || @coverage.empty?

        (@coverage.files_for(tests) | @coverage.boot_files | unobserved_files).sort
      end

      # Loaded sources the map never observed (no line, method, or load
      # evidence): coverage cannot say whether they matter, so a change in
      # any of them must invalidate (#344).
      def unobserved_files
        @fallback_files.select { |file| @coverage.empty_for?([file]) }
      end

      # RSpec ids name their file: "./spec/a_spec.rb[1:2]".
      def test_file(test)
        File.expand_path(test[/\A(.+?\.rb)(?:\[|:|\z)/, 1] || test, @root)
      end

      def file_digest(path)
        @file_digests[path] ||= File.file?(path) ? Digest::SHA256.file(path).hexdigest : "missing"
      end
    end
  end
end
