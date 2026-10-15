# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Loaded via RUBYOPT before exe/saboteur: makes a chosen require fail, to
# exercise the executable's fallback when the CLI (or the crash reporter
# itself) never loads.
module SaboteurRequireCrash
  TARGET = ENV.fetch("SABOTEUR_EXE_SPEC_REQUIRE_FAIL", "saboteur/cli").freeze
  MESSAGE = ENV.fetch("SABOTEUR_EXE_SPEC_MESSAGE", "injected require failure").freeze

  def require(name)
    raise StandardError, MESSAGE if name == TARGET

    super
  end
end

Kernel.prepend(SaboteurRequireCrash)
