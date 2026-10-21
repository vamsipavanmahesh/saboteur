# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "lib/saboteur/version"

Gem::Specification.new do |spec|
  spec.name = "saboteur"
  spec.version = Saboteur::VERSION
  spec.authors = ["Vamsi Pavan Mahesh Gunturu"]
  spec.email = ["gvpmahesh@gmail.com"]

  spec.summary = "Mutation testing for Ruby, driven by per-test coverage."
  spec.description = <<~DESC
    saboteur makes small deliberate changes to your methods, runs only the tests
    that cover each change, and reports the changes no test notices.
  DESC
  spec.homepage = "https://github.com/vamsipavanmahesh/saboteur"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "lib/saboteur/reporter/assets/*", "exe/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["saboteur"]
  spec.require_paths = ["lib"]

  # Ruby 3.3 bundles prism 0.19, whose API predates 1.0. Require a 1.x gem
  # with the node names saboteur uses (IfNode#subsequent, UnlessNode#else_clause).
  # fiddle ships WITH Ruby (a default gem on 3.x, a bundled gem from
  # 4.0), so declaring it here only forced a source build that dies on a
  # box without libffi headers (#639). The sandbox layers load it lazily
  # through Execution::FiddleLoader and refuse with the fixes when it
  # cannot load; on Ruby 4.0+ a Gemfile needs `gem "fiddle"` explicitly.
  spec.add_dependency "prism", ">= 1.2", "< 2"
end
