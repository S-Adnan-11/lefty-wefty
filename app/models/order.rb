class Order < ApplicationRecord
  MAX_AMOUNT = 9_223_372_036_854_775_807
  belongs_to :business
  belongs_to :confirmed_by, class_name: "User", optional: true
  belongs_to :voided_by, class_name: "User", optional: true
  has_many :order_items, dependent: :destroy
  has_many :products, through: :order_items
  attr_readonly :business_id, :submission_key, :creation_digest

  validates :state, inclusion: { in: %w[draft confirmed voided] }
  validates :total_minor, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_AMOUNT }

  def draft?
    state == "draft"
  end

  def confirmed?
    state == "confirmed"
  end

  def voided?
    state == "voided"
  end
end
