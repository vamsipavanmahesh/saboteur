# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"

# Panel control for #234: a literal mutation turning "logs" into "" makes the
# call delete the tool's own cache, while tracked files stay intact.
class Cleaner
  def purge
    FileUtils.rm_rf(File.join(Dir.pwd, ".saboteur", "logs"))
  end
end
