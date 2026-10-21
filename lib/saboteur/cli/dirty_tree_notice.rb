# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../reporter/palette"
require_relative "../reporter/notice"

module Saboteur
  class CLI
    # The uncommitted-work warning printed before a run (#334). Extracted
    # from CLI.
    module DirtyTreeNotice
      private

      # Mutants run your code, and a mutant of code that writes or deletes files
      # can change the tree. Say so up front when uncommitted work is at stake.
      # The scope the warning names is the configured one: positional source
      # operands narrow the run after the warning, so the include/exclude they
      # imply stay out of its config (#309, #503 review).
      def warn_dirty_tree
        warning = if @sources
                    Config.load(path: options[:config],
                                overrides: overrides.except(:include,
                                                            :exclude))
                  else
                    config
                  end
        DirtyTreeWarning.for(warning, config_path: options[:config])&.then do |text|
          palette = Reporter::Palette.for(@err, mode: @color || :auto, overrides: warning["palette"])
          @err.puts(Reporter::Notice.paint(palette, text))
        end
      end
    end
  end
end
