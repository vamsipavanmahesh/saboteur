# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Aliased
  def original_name
    6 * 7
  end

  alias_method :alias_name, :original_name
end
