# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"

# Panel control for #234: the unchanged code deletes only the project's own
# throwaway .saboteur/trash dir. A literal mutation turning "trash" into
# "logs" (or "") redirects the deletion onto the tool's own cache, so a
# vanished run file is attributable to the mutant alone. #total runs first
# and its mutants die normally, so the aborted run still shows real kills.
class Cleaner
  def total(prices)
    prices.sum
  end

  def purge
    FileUtils.rm_rf(File.join(Dir.pwd, ".saboteur", "trash"))
  end
end
