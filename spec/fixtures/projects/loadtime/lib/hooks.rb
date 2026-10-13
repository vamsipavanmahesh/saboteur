# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Hooks
  def self.label_for(name)
    name.to_s.length
  end

  def self.included(base)
    labels << label_for(base.name)
  end

  def self.labels
    @labels ||= []
  end
end

class Widget
  include Hooks

  def self.tune(factor = nil)
    if factor
      factor * 2
    else
      1 + 1
    end
  end

  def size_of(box)
    box > 10 ? "big" : "small"
  end
end

Widget.tune
