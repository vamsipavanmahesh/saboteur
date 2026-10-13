# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # Method and UnboundMethod objects captured before a re-evaluation keep
    # pointing at the original body; a handler registry such as
    # `RULES = [Limits.method(:min_ok?)]` is the common case. Tests that call
    # through such a capture can never observe a mutant, so after each
    # re-evaluation the child scans for captures of the original def.
    module StaleCaptures
      # "file:line" sites of the original def for which a stale capture
      # exists, deduplicated. Empty when nothing captured the method.
      def self.scan(reevaluator, subject)
        owner = reevaluator.resolve_owner(subject)
        target = subject.singleton ? owner.singleton_class : owner
        current = target.instance_method(subject.name)
        # A def-time wrapper (sorbet's sig) is what instance_method returns;
        # the def it dispatches to is the definition captures can hold.
        current = Wrapper.original_def(current) || current
        # The scan must not mistake transient Method objects of its own
        # making (the re-eval, this instance_method) for captures; a full GC
        # clears them, and only long-lived captures from load time remain.
        GC.start
        stale = [UnboundMethod, Method].flat_map do |kind|
          ObjectSpace.each_object(kind).select do |captured|
            stale?(captured, target, subject, current)
          end
        end
        stale.map { |captured| captured.source_location.join(":") }.uniq
      end

      def self.stale?(captured, target, subject, current)
        return false unless captured.owner == target && captured.name == subject.name
        return false if captured == current

        file, line = captured.source_location
        file && line == subject.start_line &&
          Selection::CoverageMap.canonical(file) == Selection::CoverageMap.canonical(subject.file)
      end
    end
  end
end
