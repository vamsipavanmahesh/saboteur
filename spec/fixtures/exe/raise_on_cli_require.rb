# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Loaded via RUBYOPT before exe/saboteur: makes require "saboteur/cli"
# fail, to exercise the executable's fallback when the CLI never loads.
module SaboteurRequireCrash
  def require(name)
    raise StandardError, "injected require failure" if name == "saboteur/cli"

    super
  end
end

Kernel.prepend(SaboteurRequireCrash)
