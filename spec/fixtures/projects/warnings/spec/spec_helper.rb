# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/meter"
# dry-rb/hanami-style strict warnings (issue #603): every warning raises.
# Warning.process needs Ruby 4; overriding Warning.warn is its 3.4 twin.
module Warning
  def warn(message) = raise(message)
end
