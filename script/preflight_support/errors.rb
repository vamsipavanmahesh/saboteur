# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  # The arguments are wrong. Exit 2.
  class InvalidInvocation < StandardError; end

  # The request is fine but the checkout cannot be verified as the exact head: missing commit, HEAD
  # mismatch, dirty tree, hidden edits. Exit 2.
  class UnverifiableInput < StandardError; end

  # The checks could not run to a trustworthy answer: an unreadable required input, a document that
  # cannot be parsed, an output that cannot be written. Exit 3, recorded as incomplete.
  class ExecutionGap < StandardError; end

  class MalformedDocument < ExecutionGap; end
end
