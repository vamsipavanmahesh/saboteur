# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rails/generators"
require "saboteur/install"

module Saboteur
  module Generators
    # rails generate saboteur:install [--force]
    class InstallGenerator < Rails::Generators::Base
      desc "Writes .saboteur.yml, bin/saboteur and a .gitignore entry for a Rails + RSpec app."

      def install_saboteur
        installer = Saboteur::Install.new(root: destination_root, force: options[:force])
        installer.call.each { |result| say_status(result.status, result.path) }
        hint = installer.gemfile_hint
        say("\n#{hint}") if hint
      end
    end
  end
end
