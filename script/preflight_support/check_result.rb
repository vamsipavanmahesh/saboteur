# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  CHECK_STATUSES = %i[passed failed incomplete review_required not_applicable not_run].freeze

  # Outcome of one check. Only :passed counts as success.
  #   :passed         the check ran and found nothing wrong
  #   :failed         the check ran and found a problem
  #   :incomplete     the check could not run to a trustworthy answer
  #   :review_required the check ran; a human must read something before any result is compared
  #   :not_applicable the check does not apply to this change, with a reason
  #   :not_run        the check was skipped on purpose, with a reason
  CheckResult = Struct.new(:name, :status, :reason, :details, :commands, keyword_init: true) do
    def initialize(name:, status:, reason: nil, details: [], commands: [])
      raise ArgumentError, "unknown status #{status.inspect}" unless CHECK_STATUSES.include?(status)

      super
    end

    def to_h
      { name: name, status: status, reason: reason, details: details, commands: commands.map(&:to_h) }
    end
  end
end
