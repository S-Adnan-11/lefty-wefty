class OrderItem < ApplicationRecord
  belongs_to :business
  belongs_to :order
  belongs_to :product
  has_many :inventory_logs, dependent: :restrict_with_exception

  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: Product::MAX_QUANTITY }
  validates :product_id, uniqueness: { scope: :order_id }
end
