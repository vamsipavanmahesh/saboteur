# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "subject"

module Saboteur
  # A constant assigned a hash or array literal, as a mutation subject
  # (issue #306): `RULES = { ... }` or `TAGS = [ ... ]`, with an optional
  # trailing `.freeze`. Only --since selection creates these (see
  # Engine::SubjectSelection), and the diff scope narrows their mutants to
  # the entries the diff changed.
  #
  # A constant is not a method, so the surgical def re-evaluation does not
  # apply: mutants run by re-evaluating the whole file with the mutated
  # assignment spliced in (Execution::Reevaluator#eval_whole_file, which
  # silences the "already initialized constant" warning). Re-evaluation
  # replaces the constant's object; code that reads the constant at test
  # time sees the mutant, while anything that copied the old object at load
  # time keeps it. consumer_lines names the reads a test can cover; the
  # coverage map turns them into the mutant's tests.
  class ConstantSubject < Subject
    attr_reader :literal_node
    # { "/abs/file.rb" => [lines reading the constant] } across the include
    # set, filled in after selection (the finder sees one file at a time).
    attr_accessor :consumer_lines

    def initialize(name:, owner:, file:, node:, literal_node:, file_source:, nesting:, frozen_literals:,
                   consumer_lines: {})
      super(name:, owner:, singleton: false, sclass: false, file:, node:, file_source:, nesting:,
            frozen_literals:, sig_span: nil)
      @literal_node = literal_node
      @consumer_lines = consumer_lines
    end

    # "Shop::RULES", or "RULES" at the top level. The :: separator keeps a
    # constant's id apart from the Klass#method and Klass.method spellings.
    def id
      owner ? "#{owner}::#{name}" : name.to_s
    end

    # There is no method body to redefine: constants always take the
    # whole-file evaluation path.
    def whole_file_only?
      true
    end

    # The assignment runs while the file loads, so its lines carry the load
    # evidence; the reads of the constant in this file are the lines tests
    # can cover.
    def coverage_lines
      ((start_line..end_line).to_a + Array(consumer_lines[file])).uniq
    end

    # Every edit sits inside the literal and is observable wherever the
    # constant is read, so the assignment's own lines are the evidence that
    # the edit ran (they execute at load, never inside a test).
    def coverage_lines_for(_edit)
      (start_line..end_line).to_a
    end

    def recovers?
      false
    end
  end
end
