# SPDX-License-Identifier: MIT
# frozen_string_literal: true

namespace :claims do
  desc "Check that CHANGELOG and README claims carry (e2e:) proof references"
  task check: :check_env do
    sh "script/claims-check"
  end
end
