# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Mirrors the incident: a validation whose mutants let a test reach code
# that starts a real saboteur run.
class Gate
  def self.open?(jobs)
    jobs >= 1
  end
end
