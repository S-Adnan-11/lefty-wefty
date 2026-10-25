class Product < ApplicationRecord
  MAX_QUANTITY = 2_147_483_647
  MAX_PRICE_MINOR = 999_999_999_999

  belongs_to :business
  has_many :inventory_logs, dependent: :restrict_with_exception
  has_many :order_items, dependent: :restrict_with_exception
  has_many :orders, through: :order_items
  attr_readonly :business_id, :quantity

  normalizes :name, with: ->(value) { value.strip }
  normalizes :sku, with: ->(value) { value.strip.upcase }
  validates :name, presence: true, length: { maximum: 160 }
  validates :sku, presence: true, length: { maximum: 64 },
    format: { with: /\A[A-Z0-9][A-Z0-9._-]*\z/ }, uniqueness: { scope: :business_id }
  validates :price_minor, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_PRICE_MINOR }
  validates :low_stock_threshold, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_QUANTITY }
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_QUANTITY }
  validate :starts_at_zero, on: :create

  scope :active, -> { where(archived_at: nil) }
  scope :low_stock, -> { active.where("quantity <= low_stock_threshold") }

  def archived?
    archived_at.present?
  end

  def low_stock?
    !archived? && quantity <= low_stock_threshold
  end

  private
    def starts_at_zero
      errors.add(:quantity, "must start at zero; use an opening stock movement") unless quantity == 0
    end
end
