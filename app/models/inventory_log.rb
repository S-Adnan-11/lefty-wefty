class InventoryLog < ApplicationRecord
  belongs_to :business
  belongs_to :product
  belongs_to :actor, class_name: "User"

  validates :kind, inclusion: { in: %w[opening receipt adjustment] }
  validates :quantity_delta, numericality: { only_integer: true, other_than: 0, greater_than_or_equal_to: -Product::MAX_QUANTITY, less_than_or_equal_to: Product::MAX_QUANTITY }
  validates :resulting_balance, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: Product::MAX_QUANTITY }
  validates :reason, presence: true, length: { maximum: 500 }
  validate :same_business

  def readonly?
    persisted?
  end

  private
    def same_business
      errors.add(:product, "must belong to this business") unless product&.business_id == business_id
      errors.add(:actor, "must own this business") unless actor_id == business&.owner_id
    end
end
