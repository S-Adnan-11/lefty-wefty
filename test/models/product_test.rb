require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "normalized SKU uniqueness is enforced within each business by model and database" do
    owner = create_owner
    other = create_owner(email: "other@example.test")
    product = create_product(owner.business, sku: " book-1 ")
    assert_equal "BOOK-1", product.sku
    assert create_product(other.business, sku: "book-1").persisted?
    duplicate = owner.business.products.new(name: "Other", sku: "book-1", price_minor: 100)
    assert_not duplicate.valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      Product.transaction(requires_new: true) { duplicate.save!(validate: false) }
    end
  end

  test "zero and exact threshold are low stock and ordinary balance changes are readonly" do
    owner = create_owner
    product = create_product(owner.business)
    assert product.low_stock?
    change_stock(product, 8)
    assert product.reload.low_stock?
    change_stock(product, 1)
    assert_not product.reload.low_stock?
    assert_raises(ActiveRecord::ReadonlyAttributeError) { product.update!(quantity: 99) }
    assert_equal 9, product.reload.quantity
    assert_not owner.business.products.new(name: "Bypass", sku: "BAD", price_minor: 100, quantity: 10).valid?
  end

  test "database rejects negative balances and invalid prices without model validation" do
    product = create_product(create_owner.business)
    [ { quantity: -1 }, { low_stock_threshold: -1 }, { price_minor: 0 } ].each do |attributes|
      assert_raises(ActiveRecord::StatementInvalid) do
        Product.transaction(requires_new: true) { Product.where(id: product.id).update_all(attributes) }
      end
    end
  end
end
