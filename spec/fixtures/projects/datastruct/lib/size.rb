# frozen_string_literal: true

Size = Struct.new(:w, :h) do
  def wide?
    w > h
  end
end
