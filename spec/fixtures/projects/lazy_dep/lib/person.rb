# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Person
  def check
    require_relative "../support/helper"
    Helper.value > 10
  end
end
