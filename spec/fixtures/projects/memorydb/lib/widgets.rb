# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "active_record"

# A model over a sqlite :memory: database, the shape many gem suites have.
class Widget < ActiveRecord::Base
  def double
    number * 2
  end
end
