class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :business, foreign_key: :owner_id, inverse_of: :owner, dependent: :restrict_with_exception
  validates_associated :business
  validates :email_address, presence: true, length: { maximum: 254 },
    format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true
  validates :password, length: { minimum: 12, maximum: 72 }, allow_nil: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
