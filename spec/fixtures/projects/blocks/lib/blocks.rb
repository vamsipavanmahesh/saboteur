# frozen_string_literal: true

class Plain
  def succ(number)
    number + 1
  end
end

Covered = Data.define(:amount) do
  def doubled
    amount * 2
  end
end

Uncovered = Struct.new(:amount) do
  def tripled
    amount * 3
  end

  def nothing; end
end

# Not a class factory: the block says nothing about the owner.
Registry = Plain.then do |plain|
  plain.class_eval do
    def registered
      42
    end
  end
  plain
end
