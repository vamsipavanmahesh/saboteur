# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Environment hints for runs started the wrong way (#598, #609). Detected
  # from files, never from error text; advisory only - nothing refuses.
  module EnvironmentHints
    module_function

    # One line per detected problem, each a full sentence for the channel it
    # lands in (boot warning, doctor line, or load-failure appendix).
    def all(root, bundler_loaded: !defined?(Bundler).nil?, env: ENV)
      [bundler(root, bundler_loaded: bundler_loaded), appraisal(root, env: env)].compact
    rescue StandardError
      # An advisory hint must never stop a run (Pod 1 security review).
      []
    end

    # #598: a lockfile but no Bundler means gems resolve to whatever is
    # installed, not the lockfile's versions.
    def bundler(root, bundler_loaded: !defined?(Bundler).nil?)
      return nil unless File.file?(File.join(root, "Gemfile.lock"))
      return nil if bundler_loaded

      "Gemfile.lock found but Bundler is not loaded: gems resolve to whatever is installed, not the " \
        "lockfile's versions - run `bundle exec saboteur run`"
    end

    # #609: an Appraisal project run without BUNDLE_GEMFILE pointing into
    # gemfiles/ loads the wrong (or no) dependency set.
    def appraisal(root, env: ENV)
      appraisals = File.file?(File.join(root, "Appraisals"))
      gemfiles = Dir.glob(File.join(root, "gemfiles", "*.gemfile"))
      return nil unless appraisals || gemfiles.any?

      setting = env["BUNDLE_GEMFILE"].to_s
      under = !setting.empty? &&
              File.expand_path(setting, root).start_with?("#{File.join(File.expand_path(root), 'gemfiles')}/")
      return nil if under

      found = (appraisals ? ["Appraisals"] : []) +
              gemfiles.map { |f| sanitize(f.sub("#{File.expand_path(root)}/", "")) }
      listed = found.first(5)
      listed << "+#{found.size - 5} more" if found.size > 5
      where = setting.empty? ? "is not set" : "points outside gemfiles/ (#{sanitize(setting)})"
      "Appraisal gemfiles found (#{listed.join(', ')}) but BUNDLE_GEMFILE #{where}: run " \
        "`BUNDLE_GEMFILE=gemfiles/<name>.gemfile bundle exec saboteur run` or " \
        "`bundle exec appraisal <name> saboteur run`"
    end

    # A cloned repo can name gemfiles with terminal control characters (Pod 1
    # security review): escape them before they reach the terminal.
    def sanitize(text)
      text.scrub("?").gsub(/[\x00-\x1f\x7f\u0080-\u009f]/) { |c| format("\\x%02x", c.ord) }
    end
  end
end
