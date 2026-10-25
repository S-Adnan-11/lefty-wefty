ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: 1)
    setup { Rails.application.config.x.authentication_rate_limit_store.clear }

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    def create_owner(email: "owner@example.test", name: "Cedar Supplies")
      User.transaction do
        user = User.create!(email_address: email, password: "test owner passphrase")
        Business.create!(owner: user, name: name)
        user.reload
      end
    end

    def create_product(business, **attributes)
      business.products.create!({ name: "Notebook", sku: "BOOK-1", price_minor: 125000, low_stock_threshold: 8 }.merge(attributes))
    end

    def change_stock(product, quantity, kind: "receipt", reason: nil, key: SecureRandom.uuid)
      Stock::Apply.call(business: product.business, actor: product.business.owner, product_id: product.id,
        change: StockChange.new(kind: kind, quantity: quantity, reason: reason, operation_key: key))
    end

    # Add more helper methods to be used by all tests here...
  end
end
