# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Demo
  def noisy(value)
    puts "value is #{value}"
    value
  end

  def limit(count)
    count >= 10 ? :big : :small
  end

  def pick(flag)
    flag ? 1 : 1
  end

  def fetch_name(hash)
    hash[:name] || "anon"
  end
end
