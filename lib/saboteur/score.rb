# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # The mutation score of a group of results, with the share of it that came
  # from failed assertions and the share that came from crashes.
  #
  # value is (killed + timeout) / (killed + survived + timeout). A crash kill
  # shows the code ran and broke, not that a test checked a value, so the
  # split lets a reader see how much of the score is checked behavior.
  # Errors, resource limits and skips are outside every number here.
  class Score
    def self.of(results)
      new(results)
    end

    attr_reader :assertion_kills, :crash_kills, :unclassified_kills, :timeouts, :survivors

    def initialize(results)
      killed = results.select { |result| result.status == :killed }
      @assertion_kills = killed.count(&:assertion_kill?)
      @crash_kills = killed.count(&:crash_kill?)
      @unclassified_kills = killed.size - assertion_kills - crash_kills
      @timeouts = results.count { |result| result.status == :timeout }
      @survivors = results.count(&:survived?)
    end

    def detected
      assertion_kills + crash_kills + unclassified_kills + timeouts
    end

    def tested
      detected + survivors
    end

    # nil with nothing tested.
    def value
      share(detected)
    end

    def assertion_share
      share(assertion_kills)
    end

    def crash_share
      share(crash_kills)
    end

    def unclassified_share
      share(unclassified_kills)
    end

    def timeout_share
      share(timeouts)
    end

    # False when no kill has a recorded cause: a split would then say
    # nothing. A cause is missing for verdicts reused from a run made before
    # causes were recorded, for a test that called exit, and for a failure
    # outside any example (suite level).
    def split_known?
      assertion_kills.positive? || crash_kills.positive?
    end

    # [[label, share]]: assertion and crash always, then timeout and
    # "cause not recorded" only when there are some, so the parts add up to
    # value.
    def parts
      list = [["assertion", assertion_share], ["crash", crash_share]]
      list << ["timeout", timeout_share] if timeouts.positive?
      list << ["cause not recorded", unclassified_share] if unclassified_kills.positive?
      list
    end

    # The kill split the reports print: assertion, crash and unclassified
    # counts, with the to_h key names.
    def kill_causes_h
      to_h.slice(:assertionKills, :crashKills, :unclassifiedKills)
    end

    def to_h
      {
        score: value, tested: tested, assertionKills: assertion_kills, crashKills: crash_kills,
        unclassifiedKills: unclassified_kills, timeouts: timeouts, survivors: survivors,
        assertionShare: assertion_share, crashShare: crash_share
      }
    end

    private

    def share(count)
      tested.zero? ? nil : count.fdiv(tested)
    end
  end
end
