# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module TrivialEquivalence
  # Compiles source with one fixed set of CRuby compile options, so two
  # compilations are comparable. The options are read from the running
  # interpreter and reported with every result.
  module CompilerPin
    module_function

    def compile(source, path)
      RubyVM::InstructionSequence.compile(source, path, path, 1, options)
    end

    def options
      RubyVM::InstructionSequence.compile_option
    end

    def description
      "#{RUBY_DESCRIPTION}; compile options #{options.sort.to_h}"
    end
  end
end
