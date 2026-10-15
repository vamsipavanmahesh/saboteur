# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"

# Like the danger fixture, but through dynamic dispatch with a literal
# selector: a literal mutation inside the arguments is the same hazard
# (#240).
class Dispatcher
  def clean
    FileUtils.send(:rm_rf, File.join(Dir.pwd, "build"))
  end
end
