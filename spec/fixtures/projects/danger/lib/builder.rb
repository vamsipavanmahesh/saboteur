# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"

# The issue #102 repro: a literal mutation turning "build" into "" makes the
# call delete the whole working directory.
class Builder
  def clean
    FileUtils.rm_rf(File.join(Dir.pwd, "build"))
  end
end
