# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module MutationSource
    # Suppresses mutants that would run a destructive call with altered
    # inputs. A mutant is only kept when every edit is provably safe: either
    # the subject holds no hazardous call, or the edit removes every
    # hazardous call in the method AND its replacement introduces no new one
    # (checked by parsing the replacement, never by substring match). Edits
    # strictly inside a call, edits elsewhere in a method that contains a
    # call, and edits whose replacement re-includes a hazard (for example
    # removing a negation in front of `system(...)`, or swapping
    # `rm_rf("build")` for `rm_rf(".")`) all leave a destructive call
    # running with altered inputs and are suppressed (issue #102).
    class HazardGuard
      # "<Receiver>.<name>" for calls with a receiver, the bare name for
      # Kernel-style calls. Bare FileUtils operations are listed too, so an
      # `include FileUtils` does not disarm the guard. Any method on Open3,
      # any rmtree, and backticks/%x literals are always hazardous. Replace
      # or extend via c.hazard; run them anyway with --allow-hazardous.
      DEFAULT_HAZARD = [
        "FileUtils.rm", "FileUtils.rm_r", "FileUtils.rm_rf", "FileUtils.rm_f",
        "FileUtils.remove_dir", "FileUtils.remove_entry", "FileUtils.remove_entry_secure",
        "rm", "rm_r", "rm_rf", "rm_f", "remove_dir", "remove_entry", "remove_entry_secure",
        "File.delete", "File.unlink",
        "Dir.rmdir", "Dir.delete", "Dir.unlink",
        "IO.popen",
        "Process.spawn", "Process.exec",
        "system", "exec", "spawn", "`"
      ].freeze

      OPEN3 = /\A(::)?Open3\z/
      ALWAYS_NAMES = %w[rmtree].freeze
      KERNEL_RECEIVERS = %w[Kernel Process].freeze

      def initialize(patterns = DEFAULT_HAZARD)
        @tags = Set.new(patterns.map { |pattern| pattern.to_s.sub(/\A::/, "") })
      end

      def name
        "hazard_guard"
      end

      # candidates: [[mutation, mutated_text]]. Returns [kept, suppressed].
      def partition(candidates, subject)
        spans = hazard_spans(subject.node)
        return [candidates, []] if spans.empty?

        candidates.partition { |mutation, _| safe?(mutation, spans) }
      end

      private

      # Byte spans of hazardous calls in the node tree, with the source slice
      # of each. Inner calls are covered by the outer span, so the walk does
      # not descend into a hazardous call.
      def hazard_spans(root)
        spans = []
        stack = [root]
        until stack.empty?
          node = stack.pop
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
        # Kernel.system / Kernel.spawn / Process.spawn: the explicit-receiver
        # spelling of a bare process spawn is the same hazard.
        return true if KERNEL_RECEIVERS.include?(receiver) && @tags.include?(name)

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

      # A mutation is safe only while no hazardous call survives it: every
      # edit must destroy every span (cover it wholly with a hazard-free
      # replacement). Anything less - touching a call, or editing other
      # code in a method that still holds a call - keeps the call running
      # with altered inputs, so the mutant is suppressed.
      def safe?(mutation, spans)
        mutation.edits.all? { |edit| destroys_all?(edit, spans) }
      end

      def destroys_all?(edit, spans)
        spans.all? do |start_byte, end_byte, _slice|
          edit.start_byte <= start_byte && edit.end_byte >= end_byte
        end && replacement_clean?(edit.replacement)
      end

      # The replacement itself, parsed as code. A replacement that parses
      # and contains no hazardous call cannot run one; anything else -
      # a hazard in the new text, or text that does not parse on its own -
      # is treated as hazardous.
      def replacement_clean?(replacement)
        result = Prism.parse(replacement.to_s)
        return false unless result.success?

        hazard_spans(result.value).empty?
      end
    end
  end
end
