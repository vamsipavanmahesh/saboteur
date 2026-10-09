# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Only the adult branch is tested, so mutants in the child branch have no
# covering test and must be reported as such, not as survivors.
class Stage
  def self.for(age)
    if age < 13
      label = "child"
      label.upcase
    else
      "adult"
    end
  end
end
