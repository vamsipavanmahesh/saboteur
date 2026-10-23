# SPDX-License-Identifier: MIT
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "activerecord", ">= 7.1"
# fiddle is a bundled gem from Ruby 4.0: name it so CI keeps exercising
# the sandbox layers there (#639).
gem "fiddle", ">= 1.1"
gem "json_schemer", "~> 2.3"
gem "rake", "~> 13.0"
gem "rspec", "~> 3.13"
gem "rubocop", "~> 1.65", require: false
# Dev-only: the e2e proving saboteur keeps Ruby's Coverage for itself when
# a suite starts SimpleCov (lib/saboteur/engine/boot.rb).
gem "simplecov", require: false
gem "sqlite3", "~> 2.0"
