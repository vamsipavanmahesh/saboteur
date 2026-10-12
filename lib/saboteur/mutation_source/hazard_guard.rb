# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"

module Saboteur
  module MutationSource
    # Keeps mutants from making a destructive call more destructive than the
    # original code (issue #102): a literal mutation inside
    # FileUtils.rm_rf's arguments once deleted a user's whole working tree,
    # including .git.
    #
    # A mutation survives the guard only when the hazardous call itself does
    # not survive the edit: whole-body and statement removals replace the
    # call with text that cannot execute it. Edits strictly inside the call,
    # and edits whose replacement re-includes the call (for example removing
    # a negation in front of `system(...)`), leave it running with altered
    # inputs and are suppressed.
    class HazardGuard
      # "<Receiver>.<name>" for calls with a receiver, the bare name for
      # Kernel-style calls. Any method on Open3, any rmtree, and
      # backticks/%x literals are always hazardous. Replace or extend via
      # c.hazard; run them anyway with --allow-hazardous.
      DEFAULT_HAZARD = [
        "FileUtils.rm", "FileUtils.rm_r", "FileUtils.rm_rf", "FileUtils.rm_f",
        "FileUtils.remove_dir", "FileUtils.remove_entry", "FileUtils.remove_entry_secure",
        "File.delete", "File.unlink",
        "Dir.rmdir", "Dir.delete", "Dir.unlink",
        "IO.popen",
        "system", "exec", "spawn", "`"
      ].freeze

      OPEN3 = /\A(::)?Open3\z/
      ALWAYS_NAMES = %w[rmtree].freeze

      def initialize(patterns = DEFAULT_HAZARD)
        @tags = Set.new(patterns.map { |pattern| pattern.to_s.sub(/\A::/, "") })
      end

      def name
        "hazard_guard"
      end

      # candidates: [[mutation, mutated_text]]. Returns [kept, suppressed].
      def partition(candidates, subject)
        spans = hazard_spans(subject)
        return [candidates, []] if spans.empty?

        candidates.partition { |mutation, _| safe?(mutation, spans) }
      end

      private

      # Byte spans of hazardous calls in the subject, with the source slice
      # of each. Inner calls are covered by the outer span, so the walk does
      # not descend into a hazardous call.
      def hazard_spans(subject)
        spans = []
        stack = [subject.node]
        until stack.empty?
          node = stack.pop
          next if node.nil?

          if hazardous?(node)
            spans << [node.location.start_offset, node.location.end_offset, node.slice]
            next
          end
          stack.concat(node.compact_child_nodes)
        end
        spans
      end

      def hazardous?(node)
        case node
        when Prism::XStringNode, Prism::InterpolatedXStringNode then true
        when Prism::CallNode then hazardous_call?(node)
        else false
        end
      end

      def hazardous_call?(node)
        name = node.name.to_s
        receiver = node.receiver&.slice&.sub(/\A::/, "")
        return true if OPEN3.match?(receiver.to_s)
        return true if ALWAYS_NAMES.include?(name)

        tag = receiver ? "#{receiver}.#{name}" : name
        return true if @tags.include?(tag)

        piped_open?(node, name, receiver)
      end

      # Kernel#open with a "| command" argument spawns a process.
      def piped_open?(node, name, receiver)
        return false unless name == "open" && (receiver.nil? || receiver == "Kernel")

        first = node.arguments&.arguments&.first
        case first
        when Prism::StringNode then first.unescaped.start_with?("|")
        when Prism::InterpolatedStringNode
          part = first.parts.first
          part.is_a?(Prism::StringNode) && part.unescaped.start_with?("|")
        else false
        end
      end

      def safe?(mutation, spans)
        mutation.edits.none? { |edit| hazardous_edit?(edit, spans) }
      end

      # An edit is hazardous when it touches a hazardous call but does not
      # destroy it: the call keeps running, with altered receiver, arguments
      # or surroundings. An edit destroys the call when it covers the whole
      # span and its replacement does not bring the call's text back.
      def hazardous_edit?(edit, spans)
        spans.any? do |start_byte, end_byte, slice|
          next false unless edit.start_byte < end_byte && edit.end_byte > start_byte

          destroys = edit.start_byte <= start_byte && edit.end_byte >= end_byte &&
                     !edit.replacement.include?(slice)
          !destroys
        end
      end
    end
  end
end
