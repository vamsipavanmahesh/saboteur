# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Selection
    # Dependency trees are never changed source (#504): a vendored bundle
    # or node_modules, tracked or untracked, git-ignored or not, is
    # rejected at enumeration, so --since never lists, reads or warns on
    # it. The project-local bundler path (.bundle/config's BUNDLE_PATH)
    # joins the shield when set - the standard CI layout vendor/bundle is
    # already under vendor/. The config file itself is project
    # configuration, not vendored source, and stays visible.
    module DependencyShield
      TREES = %w[vendor/ node_modules/].freeze
      BUNDLER_CONFIG = ".bundle/config"

      module_function

      def reject_trees(paths, root)
        bundler = bundler_path(root)
        paths.reject do |path|
          next false if path == BUNDLER_CONFIG

          TREES.any? { |tree| path.start_with?(tree) } || (bundler && path.start_with?(bundler))
        end
      end

      # .bundle/config's BUNDLE_PATH as a relative directory prefix, or
      # nil when no project-local config sets one (an absolute path is the
      # system bundle, outside the tree, so nothing to shield).
      def bundler_path(root)
        config = File.join(root, ".bundle", "config")
        return unless File.file?(config)

        line = File.foreach(config).find { |entry| entry.start_with?("BUNDLE_PATH:") }
        return unless line

        value = scalar(line.split(":", 2).last.strip)
        return if value.empty?

        # BUNDLE_PATH: . (or ./) is the project root itself - the empty
        # prefix would match every path and shield the whole tree (#580) -
        # and anything outside the root is the system bundle, not project
        # source. The prefix is the normalized path, not the raw scalar:
        # ./deps/../deps shields deps/.
        base = File.expand_path(root)
        expanded = File.expand_path(value, base)
        return if expanded == base || !expanded.start_with?("#{base}/")

        "#{expanded.delete_prefix("#{base}/")}/"
      rescue SystemCallError
        nil
      end

      # The scalar after "BUNDLE_PATH:": bundler writes a bare word, but
      # YAML also allows it quoted - surrounding matching quotes are not
      # part of the path.
      def scalar(raw)
        quote = raw[0]
        return raw[1..-2] if raw.length >= 2 && raw[-1] == quote && ["'", '"'].include?(quote)

        raw
      end
    end
  end
end
