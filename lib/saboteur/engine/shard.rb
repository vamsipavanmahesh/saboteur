# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"

module Saboteur
  class Engine
    # Deterministic 1-based k/n split of the planned candidate inventory.
    # The key names the candidate, never its position, so shards stay stable
    # when an earlier subject gains or loses a mutant.
    class Shard
      FORMAT = %r{\A(\d+)/(\d+)\z}
      INVENTORY_JOINER = "\0"

      attr_reader :index, :total, :all_keys, :selected_keys, :inventory_digest

      def self.parse(value)
        match = FORMAT.match(value.to_s)
        index = match && match[1].to_i
        total = match && match[2].to_i
        return new(index, total) if match && index.positive? && total >= 2 && index <= total

        raise ConfigError, "shard must be k/n with 1 <= k <= n and n >= 2 (for example 1/4)"
      end

      def initialize(index, total)
        @index = index
        @total = total
      end

      # Returns lists in the same shape as candidate_lists: [[mutation, text]] per subject.
      def select(subjects, lists)
        keyed = subjects.zip(lists).map do |subject, list|
          keys = list.map { |mutation, _| key(subject, mutation) }
          [keys, list]
        end
        @all_keys = keyed.flat_map(&:first)
        @inventory_digest = Digest::SHA256.hexdigest(@all_keys.sort.join(INVENTORY_JOINER))
        @selected_keys = @all_keys.select { |key| shard_for(key) == index - 1 }
        selected = @selected_keys.to_set
        keyed.map do |keys, list|
          list.select.with_index { |_, position| selected.include?(keys[position]) }
        end
      end

      def planned_count = all_keys.size
      def selected_count = selected_keys.size

      def line
        "Shard #{index}/#{total}: #{selected_count} of #{planned_count} planned mutants; " \
          "inventory sha256:#{inventory_digest}; partial run"
      end

      def to_h
        { index: index, of: total, selected: selected_count, planned: planned_count,
          inventoryDigest: inventory_digest, partial: true }
      end

      private

      def key(subject, mutation)
        "#{subject.id} #{mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)}"
      end

      def shard_for(key)
        Digest::SHA256.digest(key).unpack1("Q>") % total
      end
    end
  end
end
