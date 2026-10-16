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
      SEND_NAMES = %w[send public_send __send__].freeze
      ALWAYS_NAMES = %w[rmtree].freeze
      KERNEL_RECEIVERS = %w[Kernel Process].freeze

      def initialize(patterns = DEFAULT_HAZARD)
        @tags = Set.new(patterns.map { |pattern| pattern.to_s.sub(/\A::/, "") })
      end

      def name
        "hazard_guard"
      end

      # Slices of hazardous calls that would RUN when the file holding the
      # root node is evaluated: everything outside def bodies (a method body
      # runs when called, not at load). A constant mutant re-evaluates its
      # whole file, so this is what makes that replay safe to consider (#319).
      def load_time_hazards(root)
        slices = []
        stack = [root]
        until stack.empty?
          node = stack.pop
          next if node.is_a?(Prism::DefNode)

          if hazardous?(node)
            slices << node.slice
            next
          end
          stack.concat(node.compact_child_nodes)
        end
        slices
      end

      # Calls that only load more code - and only with a plain literal
      # string argument and no block: require(build_path) or
      # require_relative(begin ... end) runs arbitrary code on every
      # replay, so it is unvetted below like any other helper call.
      SAFE_LOAD_REQUIRES = %w[require require_relative].freeze

      # Assignments whose value a replay re-runs: vetted when the value is
      # a plain literal construction.
      WRITE_NODES = [Prism::ConstantWriteNode, Prism::ConstantPathWriteNode,
                     Prism::ConstantOrWriteNode, Prism::ConstantAndWriteNode,
                     Prism::ConstantPathOrWriteNode, Prism::ConstantPathAndWriteNode,
                     Prism::LocalVariableWriteNode].freeze

      # Slices of load-time statements whose effect saboteur does not vet.
      # A constant mutant re-evaluates its whole file, so any code that runs
      # at load runs again on every mutant, outside the method hazard guard.
      # The vetted forms are narrow: require/require_relative, pure defs
      # (a body runs when called, not at load), class/module nesting with a
      # constant superclass, and constant or local writes of plain literal
      # values (a `.freeze` on the literal is looked through). Everything
      # else - helper calls, registrations, writes to disk, class factories,
      # top-level blocks - is named here, NOT proven unsafe: the check only
      # says saboteur cannot account for what re-running it does (#319).
      def unvetted_load_code(root)
        bad = []
        vet_statements(root.statements.body, bad)
        bad
      end

      # candidates: [[mutation, mutated_text]]. Returns [kept, suppressed].
      def partition(candidates, subject)
        spans = hazard_spans(subject.node)
        return [candidates, []] if spans.empty?

        candidates.partition { |mutation, _| safe?(mutation, spans) }
      end

      private

      def vet_statements(body, bad)
        body.each { |node| vet_statement(node, bad) }
      end

      def vet_statement(node, bad)
        case node
        when Prism::DefNode
          nil
        when Prism::ClassNode, Prism::ModuleNode
          vet_scope(node, bad)
        when *WRITE_NODES
          bad << node.slice unless vetted_value?(node.value)
        when Prism::CallNode
          bad << node.slice unless vetted_call?(node)
        else
          bad << node.slice
        end
      end

      def vet_scope(node, bad)
        superclass = node.respond_to?(:superclass) ? node.superclass : nil
        bad << superclass.slice if superclass && !constant_read?(superclass)
        vet_statements(node.body&.body || [], bad)
      end

      def vetted_call?(node)
        return false unless SAFE_LOAD_REQUIRES.include?(node.name.to_s) && node.receiver.nil?
        return false unless node.block.nil?

        arguments = node.arguments&.arguments || []
        arguments.length == 1 && arguments.first.is_a?(Prism::StringNode)
      end

      def constant_read?(node)
        node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
      end

      # A value whose evaluation constructs data and reads constants only:
      # literal scalars, nested arrays/hashes of the same, constant reads,
      # and `.freeze` on any of those.
      def vetted_value?(node)
        case node
        when Prism::StringNode, Prism::SymbolNode, Prism::IntegerNode, Prism::FloatNode,
             Prism::TrueNode, Prism::FalseNode, Prism::NilNode, Prism::SourceFileNode,
             Prism::ConstantReadNode, Prism::ConstantPathNode
          true
        when Prism::ArrayNode
          node.elements.all? { |element| vetted_value?(element) }
        when Prism::HashNode
          node.elements.all? do |pair|
            pair.is_a?(Prism::AssocNode) && vetted_value?(pair.key) && vetted_value?(pair.value)
          end
        when Prism::CallNode
          node.name == :freeze && node.arguments.nil? && node.block.nil? && vetted_value?(node.receiver)
        else
          false
        end
      end

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

        args = node.arguments&.arguments || []
        # obj.send(:rmtree, x) is obj.rmtree(x) with indirection (#240): the
        # resolved selector faces the same direct-call semantics, with the
        # arguments shifted past it (#294 review). A dynamic selector stays
        # out of scope, as documented.
        return true if SEND_NAMES.include?(name) && (selector = literal_selector(args.first)) &&
                       direct_hazard?(selector, receiver, args[1])

        direct_hazard?(name, receiver, args.first)
      end

      def direct_hazard?(name, receiver, first_arg)
        return true if ALWAYS_NAMES.include?(name)

        tag = receiver ? "#{receiver}.#{name}" : name
        return true if @tags.include?(tag)
        # Kernel.system / Kernel.spawn / Process.spawn: the explicit-receiver
        # spelling of a bare process spawn is the same hazard.
        return true if KERNEL_RECEIVERS.include?(receiver) && @tags.include?(name)

        piped_open?(first_arg, name, receiver)
      end

      # A literal symbol or string selector names the real call.
      def literal_selector(first)
        first.unescaped if first.is_a?(Prism::SymbolNode) || first.is_a?(Prism::StringNode)
      end

      # Kernel#open with a "| command" argument spawns a process.
      def piped_open?(first, name, receiver)
        return false unless name == "open" && (receiver.nil? || receiver == "Kernel")

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
