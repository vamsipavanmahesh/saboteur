# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module TrivialEquivalence
  # Finds calls through which running code can observe its own location or
  # its own instructions. Relaxed (line-blind) proof is refused for source
  # that contains any of them. The list is a conservative denylist, not a
  # proof that other code cannot observe lines. In particular an ordinary
  # raise exposes line numbers through backtraces, and relaxed mode accepts
  # that exposure; the measurement counts the wrong skips it causes.
  class ReflectionScan
    REFLECTIVE_CALLS = %i[
      caller caller_locations backtrace backtrace_locations __LINE__ __FILE__ __dir__ __method__ __callee__
      binding local_variables eval instance_eval class_eval module_eval instance_exec class_exec
      source_location set_trace_func trace_var TracePoint of disasm disassemble to_a ObjectSpace
      method instance_method define_method send public_send __send__ method_missing
      parameters arity RubyVM set_backtrace const_source_location
    ].to_set.freeze

    def initialize(source, path)
      @source = source
      @path = path
    end

    # Names of reflective calls found anywhere in the file's instruction sequences.
    def findings
      sequence = CompilerPin.compile(@source, @path)
      found = Set.new
      walk(sequence.to_a, found)
      found.to_a.sort
    end

    private

    def walk(value, found)
      case value
      when Array
        found << value[1][:mid] if instruction_with_call_data?(value)
        found << value[1] if constant_reference?(value) && REFLECTIVE_CALLS.include?(value[1])
        value.each { |element| walk(element, found) }
      when Hash then value.each_value { |element| walk(element, found) }
      end
      found.select! { |name| REFLECTIVE_CALLS.include?(name) }
    end

    def instruction_with_call_data?(array)
      array.first.is_a?(Symbol) && array[1].is_a?(Hash) && array[1].key?(:mid)
    end

    def constant_reference?(array)
      %i[opt_getconstant_path getconstant].include?(array.first)
    end
  end
end
