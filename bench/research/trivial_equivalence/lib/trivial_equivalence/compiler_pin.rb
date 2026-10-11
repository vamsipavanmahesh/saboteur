# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module TrivialEquivalence
  # Compiles source with one fixed set of CRuby compile options, so two
  # compilations are comparable. The options are passed explicitly (not read
  # from the ambient defaults) and the Ruby series is checked: a different
  # series raises instead of producing results under an unmeasured compiler.
  # frozen_string_literal is left to each file's magic comment.
  module CompilerPin
    PINNED_RUBY_SERIES = "3.3"
    PINNED_OPTIONS = {
      coverage_enabled: false, debug_frozen_string_literal: false, debug_level: 0, inline_const_cache: true,
      instructions_unification: false, operands_unification: true, peephole_optimization: true,
      specialized_instruction: true, tailcall_optimization: false
    }.freeze

    class UnpinnedRubyError < StandardError; end

    module_function

    def compile(source, path)
      verify_ruby_series!
      RubyVM::InstructionSequence.compile(source, path, path, 1, PINNED_OPTIONS.dup)
    end

    def verify_ruby_series!
      return if RUBY_VERSION.start_with?("#{PINNED_RUBY_SERIES}.")

      raise UnpinnedRubyError, "measured on Ruby #{PINNED_RUBY_SERIES}.x only, running #{RUBY_VERSION}"
    end

    def description
      "#{RUBY_DESCRIPTION}; pinned compile options #{PINNED_OPTIONS}"
    end
  end
end
