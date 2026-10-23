# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rails/generators"
require "saboteur/install"

module Saboteur
  module Generators
    # rails generate saboteur:install [--force]
    class InstallGenerator < Rails::Generators::Base
      desc "Writes config/saboteur.rb, bin/saboteur, a .gitignore entry and the CI workflows " \
           "for a Rails + RSpec app."
      class_option :ci, type: :boolean, default: true,
                        desc: "Also write the GitHub Actions workflows for the whole-suite map (--no-ci skips them)"

      def install_saboteur
        installer = Saboteur::Install.new(root: destination_root, force: options[:force])
        results = installer.call
        results += installer.ci_workflows if options[:ci]
        results.each { |result| say_status(result.status, result.path) }
        say("\n#{Saboteur::Install::Workflows::NEXT_STEP}") if options[:ci]
        hint = installer.gemfile_hint
        say("\n#{hint}") if hint
      end
    end
  end
end
