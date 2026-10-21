# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "json"

require_relative "completeness"

module Saboteur
  module Baseline
    # Validated, immutable human acceptance and the complete run it describes.
    class Manifest
      FORMAT = 1
      METADATA = %w[generator runtime config scope snapshot subjects complete proposable issues].freeze
      # Baselines written before the two-tier completeness split carry no
      # proposable key; their strict complete flag is the proposability gate.
      LEGACY_METADATA = (METADATA - %w[proposable]).freeze
      STATUSES = %w[killed survived timeout].freeze

      attr_reader :candidates, :accepted

      def initialize(document)
        @document = JSON.parse(JSON.generate(document))
        fields!(@document, %w[format identity_version metadata candidates accepted], "manifest")
        fail!("format") unless @document["format"] == FORMAT
        fail!("identity version") unless @document["identity_version"] == 1
        validate_metadata
        validate_results
        freeze_tree(@document)
        candidates.freeze
        accepted.freeze
      rescue JSON::GeneratorError, JSON::ParserError, TypeError, ArgumentError => e
        raise ConfigError, "baseline JSON: #{e.message}"
      end

      def validate_results
        @candidates = index(@document["candidates"], "candidates") { |entry| validate_candidate(entry) }
        fail!("empty candidates") if candidates.empty?
        @accepted = index(@document["accepted"], "accepted") { |entry| validate_acceptance(entry) }
        survivors = candidates.values.select { |entry| entry["status"] == "survived" }.map { |entry| entry["id"] }
        fail!("acceptance does not cover exactly the survivors") unless accepted.keys.sort == survivors.sort
      end

      def to_h
        @document
      end

      def compatibility
        @document.fetch("metadata").slice("generator", "runtime", "config", "scope")
      end

      private

      def validate_metadata
        metadata = @document["metadata"]
        fail!("metadata fields") unless metadata.is_a?(Hash)
        keys = metadata.keys.sort
        fail!("metadata fields") unless [METADATA.sort, LEGACY_METADATA.sort].include?(keys)
        proposable = metadata.fetch("proposable", metadata["complete"])
        hard = metadata.fetch("issues").reject { |issue| Completeness.soft_gap?(issue) }
        fail!("incomplete evidence") unless proposable == true && hard.empty?
        %w[generator runtime config scope snapshot].each do |name|
          fail!("metadata #{name}") unless metadata[name].is_a?(Hash) && !metadata[name].empty?
        end
        validate_subjects(metadata["subjects"])
      end

      def validate_subjects(subjects)
        fail!("subject inventory") unless subjects.is_a?(Array) && !subjects.empty?
        subjects.each do |subject|
          fail!("subject entry") unless subject.is_a?(Array) && subject.size == 2
          path!(subject.first)
          text!(subject.last, "subject")
        end
        fail!("duplicate subjects") unless subjects.uniq.size == subjects.size
      end

      def index(entries, name)
        fail!(name) unless entries.is_a?(Array)
        entries.each_with_object({}) do |entry, dictionary|
          yield entry
          id = entry["id"]
          fail!("duplicate #{name}") if dictionary.key?(id)
          dictionary[id] = entry
        end
      end

      def validate_candidate(entry)
        fields!(entry, %w[id identity context status kill_cause], "candidate")
        tuple = entry["identity"]
        fail!("identity tuple") unless tuple.is_a?(Array) && tuple.size == 7 && tuple.first == 1
        path!(tuple[1])
        text!(tuple[2], "identity text")
        text!(tuple[3], "identity text")
        text!(tuple[4], "identity text")
        fail!("identity coarse") unless [true, false].include?(tuple[5])
        validate_edits(tuple[6])
        validate_verdict(entry, tuple)
      end

      def validate_verdict(entry, tuple)
        fail!("identity digest") unless entry["id"] == Digest::SHA256.hexdigest(JSON.generate(tuple))
        digest!(entry["context"], "context")
        fail!("status") unless STATUSES.include?(entry["status"])
        cause = entry["kill_cause"]
        text!(cause, "kill cause") unless cause.nil?
        fail!("candidate subject missing") unless @document["metadata"]["subjects"].include?(tuple[1..2])
      end

      def validate_edits(edits)
        fail!("identity edits") unless edits.is_a?(Array) && !edits.empty?
        previous = nil
        edits.each do |edit|
          fail!("identity edit") unless edit.is_a?(Array) && edit.size == 4
          validate_edit(edit)
          fail!("identity edit overlap/order") if previous && edit.first < previous
          previous = edit[1]
        end
      end

      def validate_edit(edit)
        first, last, original, replacement = edit
        fail!("identity edit range") unless first.is_a?(Integer) && last.is_a?(Integer) && first >= 0 && last >= first
        [original, replacement].each { |bytes| fail!("identity edit bytes") unless hex?(bytes) }
        fail!("identity edit length") unless original.size == (last - first) * 2
      end

      def validate_acceptance(entry)
        fields!(entry, %w[id context reason], "acceptance")
        current = candidates[entry["id"]]
        fail!("acceptance candidate") unless current && current["status"] == "survived"
        fail!("acceptance context") unless current["context"] == entry["context"]
        text!(entry["reason"], "reason")
      end

      def fields!(value, fields, name)
        fail!("#{name} fields") unless value.is_a?(Hash) && value.keys.sort == fields.sort
      end

      def path!(path)
        text!(path, "path")
        parts = path.split("/")
        fail!("path") if parts.intersect?(["", ".", ".."]) || path.include?("\\") || path.end_with?("/")
      end

      def text!(value, name)
        fail!(name) unless value.is_a?(String) && !value.strip.empty? && !value.include?("\0")
      end

      def digest!(value, name)
        fail!(name) unless value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
      end

      def hex?(value)
        value.is_a?(String) && value.match?(/\A(?:[0-9a-f]{2})*\z/)
      end

      def freeze_tree(value)
        case value
        when Hash then value.each_value do |item|
          freeze_tree(item)
        end
        when Array then value.each { |item| freeze_tree(item) }
        end
        value.freeze
      end

      def fail!(what)
        raise ConfigError, "baseline: invalid #{what}"
      end
    end
  end
end
