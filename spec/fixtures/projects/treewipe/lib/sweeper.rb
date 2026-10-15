# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"

# Issue #235 repro: a literal mutation emptying "generated" redirects the
# deletion onto lib/ itself - tracked files vanish while the run's own log
# survives, so only a per-mutant probe can name the culprit mutant.
class Sweeper
  def sweep
    FileUtils.rm_rf(File.join(Dir.pwd, "lib", "generated"))
  end
end
