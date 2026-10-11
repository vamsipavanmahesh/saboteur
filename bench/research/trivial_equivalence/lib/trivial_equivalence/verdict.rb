# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module TrivialEquivalence
  # status is :proven_equivalent or :unproven. Only a proof lets a mutant be
  # skipped; every :unproven mutant runs.
  Verdict = Data.define(:status, :reason) do
    def proven_equivalent?
      status == :proven_equivalent
    end
  end
end
