# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # Registry of gems that wrap a method at definition time. Their wrapper
    # is what Ruby runs, so the shadow guard would call every wrapped method
    # "shadowed" and skip it. A registered wrapper is instead recognized and
    # re-evaluated together with the def (see Scheduler#eval_prefix). An
    # unknown wrapper still hits the generic guard, which is the safe side.
    module Wrapper
      # :sorbet when the runtime method is sorbet-runtime's sig wrapper:
      # its source lives inside the gem and a signature is registered for it.
      def self.around(method, file)
        return nil unless file&.include?("sorbet-runtime")
        return nil unless defined?(::T::Utils) && ::T::Utils.respond_to?(:signature_for_method)
        return nil unless ::T::Utils.signature_for_method(method)

        :sorbet
      rescue StandardError
        nil
      end

      # The def a wrapper dispatches to: sorbet's runtime method is a
      # forwarding wrapper, while the registered signature holds the real
      # def. Callers comparing definitions (StaleCaptures) must compare
      # against this, or the freshly re-registered def reads as stale.
      # Real sorbet returns a Signature object (its #method is the def);
      # minimal registries return the method itself. Nil when unknown.
      def self.original_def(method)
        return nil unless around(method, method.source_location&.first) == :sorbet

        registered = ::T::Utils.signature_for_method(method)
        candidate = if registered.is_a?(Method) || registered.is_a?(UnboundMethod)
                      registered
                    elsif registered.respond_to?(:method)
                      registered.method
                    end
        candidate.is_a?(Method) || candidate.is_a?(UnboundMethod) ? candidate : nil
      rescue StandardError
        nil
      end
    end
  end
end
