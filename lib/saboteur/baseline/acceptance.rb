# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "tempfile"
require_relative "manifest"
require_relative "evidence"

module Saboteur
  module Baseline
    # Local evidence is separate from the editable proposal. This is not
    # attestation against the account owner changing both records.
    class Acceptance
      MAX_BYTES = 20 * 1024 * 1024

      def initialize(directory:, protected_paths:, verify:, require_evidence: false)
        @directory = artifact_path(directory)
        @protected = protected_paths.map { |path| Identity.canonical_path(path) }
        @verify = verify
        @require_evidence = require_evidence
      end

      def propose(document:, proposal:, destination:, previous: nil, evidence: nil)
        proposal, destination = paths(proposal, destination)
        verify_previous(destination, previous)
        validate_execution(document, evidence)
        validate_document(document)
        verify_inputs(document)
        prepare_directory
        token = SecureRandom.hex(16)
        record = { "token" => token, "destination" => destination, "previous" => previous, "document" => document }
        record["execution"] = evidence if evidence
        path = evidence_path(token)
        exclusive_write(path, record)
        exclusive_write(proposal, record)
        record
      rescue SystemCallError => e
        raise ConfigError, "baseline proposal: #{e.message}"
      end

      def accept(proposal:, destination:, previous: nil)
        proposal, destination = paths(proposal, destination)
        edited = read_record(proposal)
        prepare_directory
        original = read_record(evidence_path(edited.fetch("token")), private_record: true)
        validate_binding(original, edited, destination)
        validate_execution(edited.fetch("document"), original["execution"])
        Manifest.new(edited.fetch("document"))
        verify_inputs(original.fetch("document"))
        publish(destination, edited.fetch("document"), original.fetch("previous"), previous)
        File.unlink(evidence_path(edited.fetch("token")))
        destination
      rescue SystemCallError, KeyError => e
        raise ConfigError, "baseline evidence: #{e.message}"
      end

      private

      def paths(proposal, destination)
        list = [proposal, destination].map { |path| artifact_path(path) }
        aliases = list.first == list.last || File.identical?(*list)
        raise ConfigError, "baseline proposal and destination alias" if aliases

        if list.any? { |path| path == @directory || path.start_with?("#{@directory}/") }
          raise ConfigError, "baseline artifact aliases local evidence directory"
        end

        (list + [@directory]).each { |path| safe_path(path) }
        list
      end

      def artifact_path(path)
        expanded = File.expand_path(path)
        File.join(Identity.canonical_path(File.dirname(expanded)), File.basename(expanded))
      end

      def safe_path(path)
        current = path
        loop do
          raise ConfigError, "baseline symlink path: #{current}" if File.symlink?(current)
          break if current == File.dirname(current)

          current = File.dirname(current)
        end
        if @protected.any? do |input|
          input == path || File.identical?(input, path)
        end
          raise ConfigError, "baseline artifact aliases an input: #{path}"
        end
      end

      def prepare_directory
        FileUtils.mkdir_p(@directory, mode: 0o700)
        return if File.stat(@directory).mode.nobits?(0o077) && File.stat(@directory).uid == Process.uid

        raise ConfigError,
              "baseline evidence directory is not private"
      end

      def evidence_path(token)
        raise ConfigError, "baseline evidence token" unless token.is_a?(String) && token.match?(/\A[0-9a-f]{32}\z/)

        File.join(@directory, "#{token}.json")
      end

      def read_record(path, private_record: false)
        safe_path(path)
        if private_record && (!File.stat(path).mode.nobits?(0o077) || File.stat(path).uid != Process.uid)
          raise ConfigError, "baseline evidence record is not private"
        end
        raise ConfigError, "baseline evidence too large" if File.size(path) > MAX_BYTES

        record = File.open(path, File::RDONLY | File::NOFOLLOW) { |file| JSON.parse(file.read) }
        unless record.is_a?(Hash) && [%w[destination document previous token],
                                      %w[destination document execution previous token]].include?(record.keys.sort)
          raise ConfigError, "baseline evidence fields"
        end

        validate_nested_document(record.fetch("document"))
        record
      rescue JSON::ParserError => e
        raise ConfigError, "baseline evidence JSON: #{e.message}"
      end

      def validate_nested_document(document)
        return if document.is_a?(Hash) && document["accepted"].is_a?(Array) && document["accepted"].all?(Hash)

        raise ConfigError, "baseline proposal document or acceptance shape"
      end

      def validate_execution(document, execution)
        validate_nested_document(document)
        raise ConfigError, "baseline execution evidence missing" if @require_evidence && !execution
        return unless execution

        captured = Evidence.new(execution).manifest(reasons: "validation")
        proposed = JSON.parse(JSON.generate(document))
        proposed.fetch("accepted").each { |entry| entry["reason"] = "validation" }
        raise ConfigError, "baseline execution evidence differs" unless captured == proposed
      end

      def validate_document(document)
        copy = JSON.parse(JSON.generate(document))
        copy.fetch("accepted").each { |entry| entry["reason"] = "pending review" }
        Manifest.new(copy)
      end

      def verify_inputs(document)
        raise ConfigError, "baseline inputs changed or unverified" unless @verify.call(document.fetch("metadata"))
      end

      def validate_binding(original, edited, destination)
        raise ConfigError, "baseline destination differs from proposal" unless original["destination"] == destination

        before = JSON.parse(JSON.generate(original))
        after = JSON.parse(JSON.generate(edited))
        [before, after].each do |record|
          record.fetch("document").fetch("accepted").each do |entry|
            entry.delete("reason")
          end
        end
        raise ConfigError, "baseline proposal evidence changed" unless before == after
      end

      def verify_previous(destination, previous)
        if previous.nil?
          raise ConfigError, "baseline destination exists" if File.exist?(destination)
        elsif !File.file?(destination) || Digest::SHA256.file(destination).hexdigest != previous
          raise ConfigError, "baseline previous destination changed"
        end
      end

      def exclusive_write(path, document)
        safe_path(path)
        File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
          file.write(JSON.generate(document))
          file.flush
          file.fsync
        end
      rescue Errno::EEXIST
        raise ConfigError, "baseline output exists: #{path}"
      end

      def publish(destination, document, recorded, reviewed)
        safe_path("#{destination}.lock")
        File.open("#{destination}.lock", File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          safe_path(destination)
          raise ConfigError, "baseline replacement requires matching reviewed hash" unless recorded == reviewed

          verify_previous(destination, recorded)
          verify_inputs(document)
          replace(destination, document, initial: recorded.nil?)
        end
      end

      def replace(destination, document, initial: false)
        Tempfile.create([".baseline-", ".json"], File.dirname(destination)) do |file|
          file.chmod(0o600)
          file.write(JSON.generate(document))
          file.flush
          file.fsync
          if initial
            begin
              File.link(file.path, destination)
            rescue Errno::EEXIST
              raise ConfigError, "baseline destination exists"
            end
          else
            File.rename(file.path, destination)
          end
        end
      end
    end
  end
end
