# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Install
    # The two GitHub Actions workflows `saboteur install` writes (#1317): one
    # builds the whole-suite coverage map on main and saves it to the Actions
    # cache, the other restores it on pull requests through the saboteur
    # action. Both name the cache by the scheme action.yml restores with, so a
    # pull request finds the latest main map.
    module Workflows
      MAP_FILE = ".github/workflows/saboteur-map.yml"
      PR_FILE = ".github/workflows/saboteur-pr.yml"

      CHECKOUT = "actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4"
      SETUP_RUBY = "ruby/setup-ruby@14594264cd68ce8a2345dd349bc3d138a4ef85c8 # v1"
      CACHE_SAVE = "actions/cache/save@0057852bfaa89a56745cba8c7296529d2fc39830 # v4"

      # The cache scheme, one copy: the paths hold the map, its inputs snapshot
      # and the pointer to the freshest whole-suite map (a map without the
      # pointer is not read as whole-suite). action.yml restores the same list.
      CACHE_PATHS = %w[.saboteur/coverage-*.json .saboteur/inputs-*.json .saboteur/whole-suite-map-v2].freeze
      HASHED = %w[Gemfile.lock config/saboteur.rb config/saboteur_custom_map.rb config/saboteur_ignore.rb].freeze
      CACHE_PREFIX = "saboteur-${{ runner.os }}-${{ hashFiles(#{HASHED.map do |file|
        "'#{file}'"
      end.join(', ')}) }}-".freeze
      CACHE_KEY = "#{CACHE_PREFIX}${{ github.sha }}".freeze

      NEXT_STEP = "Next: commit both files and push to main. The main workflow runs your whole suite and " \
                  "mutates the whole project once to build the map (docs/ci-whole-suite-map.md); pull " \
                  "requests restore it from the cache."

      module_function

      def files(ruby_version_file: false)
        { MAP_FILE => map_workflow(ruby_version_file), PR_FILE => pr_workflow(ruby_version_file) }
      end

      def ruby_setup(ruby_version_file)
        ["- uses: #{SETUP_RUBY}", "  with:",
         *(ruby_version_file ? [] : ['    ruby-version: "3.3"']),
         "    bundler-cache: true",
         "# Add your database, services and any other setup your specs need here."].join("\n")
      end

      def map_workflow(ruby_version_file)
        <<~YAML
          # Builds the whole-suite coverage map on main so pull requests can confirm
          # survivors against specs they did not load. Written by `saboteur install`.
          name: Saboteur map
          on:
            push:
              branches: [main]
            workflow_dispatch:
            # schedule:
            #   - cron: "17 3 * * 1"
          permissions:
            contents: read
          jobs:
            map:
              runs-on: ubuntu-latest
              timeout-minutes: 120
              steps:
                - uses: #{CHECKOUT}
                  with:
                    fetch-depth: 1
          #{indent(ruby_setup(ruby_version_file), 6)}
                - name: Build the whole-suite map
                  run: |
                    status=0
                    bundle exec saboteur run --all || status=$?
                    # Exit 1 means survivors: the map is still built and saved below.
                    [ "$status" -le 1 ] || exit "$status"
                - name: Save the map
                  if: always() && hashFiles('.saboteur/whole-suite-map-v2') != ''
                  uses: #{CACHE_SAVE}
                  with:
                    path: |
          #{indent(CACHE_PATHS.join("\n"), 12)}
                    key: #{CACHE_KEY}
        YAML
      end

      def pr_workflow(ruby_version_file)
        <<~YAML
          # Mutates the lines a pull request changed and comments the survivors. The
          # action restores the map the main workflow saved. Written by `saboteur install`.
          name: Saboteur
          on: pull_request
          permissions:
            contents: read
            pull-requests: write
          jobs:
            mutation:
              runs-on: ubuntu-latest
              steps:
                - uses: #{CHECKOUT}
                  with:
                    fetch-depth: 1
          #{indent(ruby_setup(ruby_version_file), 6)}
                # Pin this to a release tag once one contains the whole-suite map cache.
                - uses: vamsipavanmahesh/saboteur@main
                  with:
                    # The settings of `saboteur pr`: one baseline check, a 10 minute budget.
                    arguments: --baseline-passes 1
                    max-duration: 10m
                    review-comments: "true"
        YAML
      end

      def indent(text, spaces)
        text.lines.map { |line| (" " * spaces) + line }.join
      end
    end
  end
end
