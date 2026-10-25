require "test_helper"

class StockTest < ActiveSupport::TestCase
  setup do
    @owner = create_owner
    @product = create_product(@owner.business)
  end

  test "receipt retry and adjustment reconcile with an append-only ledger" do
    key = SecureRandom.uuid
    first = change_stock(@product, 10, key: key)
    assert_equal first.id, change_stock(@product, "10", key: key).id
    assert_equal 10, @product.reload.quantity
    assert_equal 1, @product.inventory_logs.count
    change_stock(@product, -2, kind: "adjustment", reason: "Damaged units")
    assert_equal 8, @product.reload.quantity
    assert @product.low_stock?
    assert_equal 8, @product.inventory_logs.sum(:quantity_delta)
    assert_equal [ 10, 8 ], @product.inventory_logs.order(:id).pluck(:resulting_balance)
    assert_raises(ActiveRecord::ReadOnlyRecord) { first.update!(reason: "Rewritten") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { first.destroy! }
    assert_raises(ActiveRecord::StatementInvalid) do
      InventoryLog.transaction(requires_new: true) { InventoryLog.where(id: first.id).update_all(reason: "Rewritten") }
    end
  end

  test "negative, invalid, overflowing and conflicting submissions change nothing" do
    key = SecureRandom.uuid
    change_stock(@product, 10, key: key)
    attempts = [
      -> { change_stock(@product, -11, kind: "adjustment", reason: "Count correction") },
      -> { change_stock(@product, 1, kind: "adjustment", reason: " ") },
      -> { change_stock(@product, 0) }, -> { change_stock(@product, -1) },
      -> { change_stock(@product, "1.5") }, -> { change_stock(@product, "2units") },
      -> { change_stock(@product, Product::MAX_QUANTITY + 1) },
      -> { change_stock(@product, Product::MAX_QUANTITY) },
      -> { change_stock(@product, 11, key: key) },
      -> { change_stock(@product, 1, key: "not-a-uuid") }
    ]
    attempts.each do |attempt|
      assert_no_difference "InventoryLog.count" do
        assert_raises(Stock::Apply::Rejected, &attempt)
      end
      assert_equal 10, @product.reload.quantity
    end
  end

  test "database error after the movement insert rolls back the whole operation" do
    Product.connection.execute <<~SQL
      CREATE FUNCTION reject_test_balance() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'forced test failure'; END; $$;
      CREATE TRIGGER reject_test_balance BEFORE UPDATE OF quantity ON products
        FOR EACH ROW EXECUTE FUNCTION reject_test_balance();
    SQL
    assert_no_difference "InventoryLog.count" do
      assert_raises(ActiveRecord::StatementInvalid) do
        Product.transaction(requires_new: true) { change_stock(@product, 10) }
      end
    end
    assert_equal 0, @product.reload.quantity
  end

  test "opening stock is atomic with product creation" do
    product = @owner.business.products.new(name: "Pencil", sku: "PEN", price_minor: 500, low_stock_threshold: 0)
    assert Products::Create.call(product: product, actor: @owner, opening_quantity: "5")
    assert_equal 5, product.reload.quantity
    assert_equal [ "opening" ], product.inventory_logs.pluck(:kind)
    invalid = @owner.business.products.new(name: "Bad", sku: "BAD", price_minor: 500)
    assert_no_difference [ "Product.count", "InventoryLog.count" ] do
      assert_not Products::Create.call(product: invalid, actor: @owner, opening_quantity: "1.2")
    end
    wrong_actor = create_owner(email: "other@example.test")
    another = @owner.business.products.new(name: "Atomic", sku: "ATOMIC", price_minor: 500)
    assert_no_difference [ "Product.count", "InventoryLog.count" ] do
      assert_not Products::Create.call(product: another, actor: wrong_actor, opening_quantity: "3")
    end
  end

  test "archive retains stock and ledger and rejects new changes" do
    key = SecureRandom.uuid
    movement = change_stock(@product, 10, key: key)
    @product.update!(archived_at: Time.current)
    assert_not @product.low_stock?
    assert_equal movement.id, change_stock(@product, 10, key: key).id
    assert_raises(Stock::Apply::Rejected) { change_stock(@product, 1) }
    assert_equal 10, @product.reload.quantity
    assert_equal 10, @product.inventory_logs.sum(:quantity_delta)
    assert_raises(ActiveRecord::DeleteRestrictionError) { @product.destroy! }
  end

  test "foreign actor and forged product associations fail in the service and database" do
    other = create_owner(email: "other@example.test")
    foreign_product = create_product(other.business)
    assert_raises(ActiveRecord::RecordNotFound) do
      Stock::Apply.call(business: @owner.business, actor: @owner, product_id: foreign_product.id,
        change: StockChange.new(kind: "receipt", quantity: 1, operation_key: SecureRandom.uuid))
    end
    assert_raises(Stock::Apply::Rejected) do
      Stock::Apply.call(business: @owner.business, actor: other, product_id: @product.id,
        change: StockChange.new(kind: "receipt", quantity: 1, operation_key: SecureRandom.uuid))
    end
    [ { product_id: foreign_product.id, actor_id: @owner.id }, { product_id: @product.id, actor_id: other.id } ].each do |forged|
      assert_raises(ActiveRecord::InvalidForeignKey) do
        InventoryLog.transaction(requires_new: true) do
          InventoryLog.insert_all!([ { business_id: @owner.business.id, operation_key: SecureRandom.uuid, kind: "receipt", quantity_delta: 1, resulting_balance: 1, reason: "Forged", created_at: Time.current }.merge(forged) ])
        end
      end
    end
  end
end
