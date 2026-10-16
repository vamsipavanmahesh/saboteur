# frozen_string_literal: true

Point = Data.define(:x, :y) do
  def above?
    y > x
  end

  def self.origin
    new(0, 0)
  end
end
