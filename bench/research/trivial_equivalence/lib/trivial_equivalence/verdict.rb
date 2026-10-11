# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module TrivialEquivalence
  # status is :fingerprint_match or :no_match.
  #
  # A match means the two files compile to the same normalized instruction
  # fingerprint under the observation model in REPORT.md. It is not a proof of
  # semantic equivalence. No runtime decision should rely on it. Every
  # :no_match mutant runs.
  Verdict = Data.define(:status, :reason) do
    def fingerprint_match?
      status == :fingerprint_match
    end
  end
end
