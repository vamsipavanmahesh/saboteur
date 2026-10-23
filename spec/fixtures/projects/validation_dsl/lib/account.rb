require "active_model"

class Account
  include ActiveModel::Model
  attr_accessor :name, :age

  validates :name, presence: true, length: { maximum: 20 }
  validates :age, numericality: { greater_than: 0 }, if: :adult?

  def adult?
    true
  end
end
