# SPDX-License-Identifier: MIT
# frozen_string_literal: true

Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  c.exclude = ["lib/dry/inflector/version.rb"]
end
