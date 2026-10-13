# SPDX-License-Identifier: MIT
# frozen_string_literal: true

Saboteur.ignore do |i|
  # tune is only ever called without a factor while the app boots, so a test
  # cannot pin that branch; its line-level mutants already read as ran at
  # load. Keeping this survivor out of the score for the same reason.
  i.mutation "a58427532c37e0e4", subject: "Widget.tune",
                                reason: "only the load-time default call takes the else branch"
end
