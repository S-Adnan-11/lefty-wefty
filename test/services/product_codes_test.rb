require "test_helper"

class ProductCodesTest < ActiveSupport::TestCase
  test "generated code collisions retry boundedly while custom uniqueness stays scoped" do
    owner = create_owner
    existing = create_product(owner.business, sku: "LW-11111111")
    product = owner.business.products.new(name: "Generated", price_minor: 100, low_stock_threshold: 0)
    product.define_singleton_method(:generate_code) do
      @code_attempts = (@code_attempts || 0) + 1
      self.sku = @code_attempts == 1 ? "LW-11111111" : "LW-22222222" if sku.blank?
    end
    assert Products::Create.call(product: product, actor: owner, opening_quantity: 0)
    assert_equal "LW-22222222", product.sku
    blocked = owner.business.products.new(name: "Collision", price_minor: 100, low_stock_threshold: 0)
    blocked.define_singleton_method(:generate_code) { self.sku = "LW-11111111" if sku.blank? }
    assert_no_difference "Product.count" do
      assert_not Products::Create.call(product: blocked, actor: owner, opening_quantity: 0)
    end
    assert blocked.errors.any?
    custom = owner.business.products.new(name: "Duplicate", sku: existing.sku, price_minor: 100)
    assert_not Products::Create.call(product: custom, actor: owner, opening_quantity: 0)
    other = create_owner(email: "other@example.test")
    assert create_product(other.business, sku: existing.sku).persisted?
  end

  test "database unique conflict retries inside savepoint without losing starting stock" do
    owner = create_owner
    product = owner.business.products.new(name: "Generated", price_minor: 100, low_stock_threshold: 0)
    original = product.method(:save!)
    attempts = 0
    product.define_singleton_method(:save!) do
      attempts += 1
      raise ActiveRecord::RecordNotUnique if attempts == 1
      original.call
    end
    assert Products::Create.call(product: product, actor: owner, opening_quantity: 3)
    assert_equal 2, attempts
    assert_equal 3, product.reload.quantity
    assert_equal 1, product.inventory_logs.count
  end
end
