class Business < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :products, dependent: :restrict_with_exception
  has_many :inventory_logs, dependent: :restrict_with_exception

  attr_readonly :owner_id, :currency, :timezone
  normalizes :name, with: ->(name) { name.strip }
  validates :name, presence: true, length: { maximum: 120 }
  validates :owner_id, uniqueness: true
  validates :currency, inclusion: { in: [ "NGN" ] }
  validates :timezone, inclusion: { in: [ "Africa/Lagos" ] }
end
