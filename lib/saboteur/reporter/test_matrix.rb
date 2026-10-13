# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # What a --matrix run says about the tests themselves. Every covering test
    # ran against every mutant, so each killed mutant lists all of its
    # killers. A blind test covered mutants and killed none of them. A
    # redundant test killed some, and every one of those had another killer.
    #
    # Only mutants whose every planned test is known to have run (see
    # MutantResult#complete?) count. A run that stopped early or could not
    # report what it ran is an incomplete mutant: the tests planned for it
    # are unverified, and no blind or redundant verdict is given for them.
    class TestMatrix
      MAX_LISTED = 20

      attr_reader :blind, :redundant, :tests, :incomplete

      def initialize(results)
        executed = results.select { |result| %i[killed survived].include?(result.status) }
        complete, partial = executed.partition(&:complete?)
        @incomplete = partial.size
        @covered = Hash.new(0)
        @killed = Hash.new { |hash, test| hash[test] = [] }
        complete.each { |result| tally(result) }
        @unverified = partial.flat_map(&:covered_by).uniq
        @tests = @covered.keys.sort
        judged = @tests - @unverified
        @blind = judged.select { |test| @killed[test].empty? }
        @redundant = judged.select { |test| redundant?(test) }
      end

      def mutants_covered(test)
        @covered.fetch(test)
      end

      def mutants_killed(test)
        @killed[test].size
      end

      private

      def tally(result)
        key = [result.subject.id, result.digest]
        result.covered_by.each { |test| @covered[test] += 1 }
        killers = result.killed_by & result.covered_by
        killers.each { |test| @killed[test] << [key, killers.size - 1] }
      end

      def redundant?(test)
        kills = @killed[test]
        kills.any? && kills.all? { |_key, others| others.positive? }
      end
    end
  end
end
