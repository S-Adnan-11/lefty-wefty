require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "fictional seeds preserve existing accounts products and stock when repeated" do
    load Rails.root.join("db/seeds.rb")
    assert_equal 2, Business.count
    assert_equal 4, Product.count
    assert_equal 2, Product.where(sku: "BOOK-1").count
    product = User.find_by!(email_address: "cedar@example.test").business.products.find_by!(sku: "BOOK-1")
    change_stock(product, -1, kind: "adjustment", reason: "Seed rerun preservation test")
    digest = product.business.owner.password_digest
    product.update!(name: "Edited notebook")
    counts = [ User.count, Business.count, Product.count, InventoryLog.count ]
    load Rails.root.join("db/seeds.rb")
    assert_equal counts, [ User.count, Business.count, Product.count, InventoryLog.count ]
    assert_equal 9, product.reload.quantity
    assert_equal "Edited notebook", product.name
    assert_equal digest, product.business.owner.reload.password_digest
  end
end
