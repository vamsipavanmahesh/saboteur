# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "active_record"

# The #387 shape: connect to sqlite :memory: and load the schema at require
# time, so the schema lives only in this process's connection.
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.define do
  create_table :widgets do |table|
    table.integer :number
  end
end

require_relative "../lib/widgets"
