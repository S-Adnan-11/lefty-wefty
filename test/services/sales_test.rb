require "test_helper"

class SalesTest < ActiveSupport::TestCase
  setup do
    @owner = create_owner
    @business = @owner.business
    @product = create_product(@business)
    change_stock(@product, 10)
  end

  test "draft then confirm then void records immutable linked history and reconciles" do
    order = draft
    assert_equal 10, @product.reload.quantity
    assert_equal 1, @product.inventory_logs.count
    assert_equal 375000, order.total_minor
    assert_equal order.id, confirm(order).id
    assert_equal 7, @product.reload.quantity
    assert @product.low_stock?
    assert_equal 1, @product.inventory_logs.where(kind: "sale").count
    original = order.order_items.reload.sole.attributes
    @product.update!(name: "Revised name", sku: "REVISED", price_minor: 900, archived_at: Time.current)
    assert_equal original, order.order_items.reload.sole.attributes
    assert_equal 375000, order.reload.total_minor
    assert_equal order.id, confirm(order, revision: -1, review_token: "old").id
    result = void(order)
    assert result.voided?
    assert_equal 10, @product.reload.quantity
    assert @product.archived?
    deduction = @product.inventory_logs.find_by!(kind: "sale")
    reversal = @product.inventory_logs.find_by!(kind: "sale_void")
    assert_equal deduction.id, reversal.reversal_of_id
    assert_equal deduction.order_item_id, reversal.order_item_id
    assert_equal 3, reversal.quantity_delta
    recorded = result.attributes
    assert_equal recorded, void(order).attributes
    assert_raises(Sales::Rejected) { void(order, reason: "Different") }
    assert_equal recorded, order.reload.attributes
    assert confirm(order).voided?
    assert_equal 3, @product.inventory_logs.count
    reconcile
  end

  test "draft identity returns the same saved order and rejects conflicting reuse" do
    key = SecureRandom.uuid
    order = draft(submission_key: key)
    assert_equal order.id, draft(submission_key: key).id
    assert_equal order.id, draft(submission_key: key, lines: [ { product_id: @product.id.to_s, quantity: "3" } ]).id
    assert_raises(Sales::Rejected) { draft(submission_key: key, lines: [ { product_id: @product.id, quantity: 2 } ]) }
    confirm(order)
    assert draft(submission_key: key).confirmed?
    assert_equal 1, @business.orders.count
    assert_equal 7, @product.reload.quantity
  end

  test "invalid empty duplicate fractional overflowing and foreign draft lines have no effects" do
    other = create_owner(email: "other@example.test")
    foreign = create_product(other.business)
    invalid = [ [], [ { product_id: @product.id, quantity: 0 } ], [ { product_id: @product.id, quantity: "1.5" } ],
      [ { product_id: @product.id, quantity: "2units" } ], [ { product_id: @product.id, quantity: Product::MAX_QUANTITY + 1 } ],
      [ { product_id: foreign.id, quantity: 1 } ], [ { product_id: 999999999, quantity: 1 } ],
      [ { product_id: @product.id, quantity: 1 }, { product_id: @product.id, quantity: 2 } ] ]
    invalid.each do |lines|
      assert_no_difference [ "Order.count", "OrderItem.count", "InventoryLog.count" ] do
        assert_raises(Sales::Rejected) { draft(lines: lines) }
      end
    end
    assert_raises(Sales::Rejected) { draft(submission_key: "bad") }
    assert_raises(Sales::Rejected) { Sales::Draft.call(business: @business, actor: other, lines: [], submission_key: SecureRandom.uuid) }
    @product.update!(price_minor: Product::MAX_PRICE_MINOR)
    assert_raises(Sales::Rejected) { draft(lines: [ { product_id: @product.id, quantity: Product::MAX_QUANTITY } ]) }
    reconcile
  end

  test "multi item insufficient stock rolls back prior deduction snapshot and confirmation" do
    second = create_product(@business, sku: "SECOND")
    order = draft(lines: [ { product_id: second.id, quantity: 1 }, { product_id: @product.id, quantity: 3 } ])
    original = order.attributes
    assert_no_difference "InventoryLog.count" do
      assert_raises(Stock::Apply::Rejected) { confirm(order) }
    end
    assert_equal original, order.reload.attributes
    assert order.order_items.all? { |item| item.reload.unit_price_minor.nil? }
    assert_equal 10, @product.reload.quantity
    assert_equal 0, second.reload.quantity
    change_stock(second, 1)
    confirm(order)
    assert_equal 2, InventoryLog.where(kind: "sale", order_item_id: order.order_item_ids).count
    reconcile
  end

  test "controlled failure after a first line rolls back all sale writes" do
    second = create_product(@business, sku: "SECOND")
    change_stock(second, 5)
    order = draft(lines: [ { product_id: @product.id, quantity: 3 }, { product_id: second.id, quantity: 2 } ])
    Product.connection.execute <<~SQL
      CREATE FUNCTION reject_sale_test_balance() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN IF NEW.id = #{second.id} THEN RAISE EXCEPTION 'forced second-line write failure'; END IF; RETURN NEW; END; $$;
      CREATE TRIGGER reject_sale_test_balance BEFORE UPDATE OF quantity ON products
        FOR EACH ROW EXECUTE FUNCTION reject_sale_test_balance();
    SQL
    assert_no_difference "InventoryLog.count" do
      assert_raises(ActiveRecord::StatementInvalid) do
        Order.transaction(requires_new: true) { confirm(order) }
      end
    end
    assert order.reload.draft?
    assert_nil order.confirmed_at
    assert order.order_items.reload.all? { |item| item.unit_price_minor.nil? }
    assert_equal [ 10, 5 ], [ @product.reload.quantity, second.reload.quantity ]
    reconcile
  end

  test "void failure after a first reversal rolls back both state and every reversal" do
    second = create_product(@business, sku: "SECOND")
    change_stock(second, 5)
    order = draft(lines: [ { product_id: @product.id, quantity: 3 }, { product_id: second.id, quantity: 2 } ])
    confirm(order)
    Product.connection.execute <<~SQL
      CREATE FUNCTION reject_void_test_balance() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN IF NEW.id = #{second.id} THEN RAISE EXCEPTION 'forced reversal failure'; END IF; RETURN NEW; END; $$;
      CREATE TRIGGER reject_void_test_balance BEFORE UPDATE OF quantity ON products
        FOR EACH ROW EXECUTE FUNCTION reject_void_test_balance();
    SQL
    assert_no_difference "InventoryLog.count" do
      assert_raises(ActiveRecord::StatementInvalid) { Order.transaction(requires_new: true) { void(order) } }
    end
    assert order.reload.confirmed?
    assert_nil order.voided_at
    assert_equal [ 7, 3 ], [ @product.reload.quantity, second.reload.quantity ]
    reconcile
  end

  test "changed price persists a renewed quote without confirming until explicitly accepted" do
    order = draft
    revision, token = order.revision, order.review_token
    @product.update!(price_minor: 140000)
    assert_raises(Sales::ReviewChanged) { confirm(order) }
    order.reload
    assert order.draft?
    assert_equal 420000, order.total_minor
    assert_equal revision + 1, order.revision
    assert_not_equal token, order.review_token
    assert_equal 10, @product.reload.quantity
    assert_raises(Sales::ReviewChanged) { confirm(order, revision: revision, review_token: token) }
    assert_raises(Sales::ReviewChanged) { confirm(order, review_token: "crafted-amount-1") }
    confirm(order)
    assert_equal 420000, order.reload.total_minor
    reconcile
  end

  test "editing and discarding use the saved revision and do not affect stock" do
    order = draft
    old_revision, old_token = order.revision, order.review_token
    Sales::Draft.call(business: @business, actor: @owner, order_id: order.id, revision: old_revision,
      lines: [ { product_id: @product.id, quantity: 4 } ])
    order.reload
    assert_raises(Sales::ReviewChanged) { confirm(order, revision: old_revision, review_token: old_token) }
    assert_raises(Sales::ReviewChanged) do
      Sales::Draft.call(business: @business, actor: @owner, order_id: order.id, revision: old_revision,
        lines: [ { product_id: @product.id, quantity: 7 } ])
    end
    assert_raises(Sales::ReviewChanged) { Sales::Draft.discard(business: @business, actor: @owner, order_id: order.id, revision: old_revision) }
    Sales::Draft.discard(business: @business, actor: @owner, order_id: order.id, revision: order.revision)
    assert_not Order.exists?(order.id)
    assert_equal 10, @product.reload.quantity
    assert_raises(Sales::Rejected) { draft(submission_key: order.submission_key) }
    reconcile
  end

  test "invalid state transitions and archived new sales leave history untouched" do
    order = draft
    assert_raises(Sales::Rejected) { void(order) }
    assert_raises(Sales::Rejected) { void(order, reason: " ") }
    assert_raises(Sales::Rejected) { void(order, acknowledged: "0") }
    @product.update!(archived_at: Time.current)
    assert_raises(Sales::Rejected) { confirm(order) }
    assert_raises(Sales::Rejected) { draft }
    @product.update!(archived_at: nil)
    confirm(order)
    assert_raises(Sales::Rejected) { Sales::Draft.discard(business: @business, actor: @owner, order_id: order.id, revision: order.revision) }
    assert_raises(Sales::Rejected) { Sales::Draft.call(business: @business, actor: @owner, order_id: order.id, revision: order.revision, lines: [ { product_id: @product.id, quantity: 1 } ]) }
    reconcile
  end

  test "database rejects cross business links malformed items and immutable recorded fields" do
    other = create_owner(email: "other@example.test")
    foreign_product = create_product(other.business)
    order = draft
    second_order = Sales::Draft.call(business: other.business, actor: other,
      lines: [ { product_id: foreign_product.id, quantity: 1 } ], submission_key: SecureRandom.uuid)
    [ { product_id: foreign_product.id }, { order_id: second_order.id }, { quantity: 0 } ].each do |attributes|
      database_rejects { OrderItem.where(id: order.order_items.sole.id).update_all(attributes) }
    end
    database_rejects { Order.where(id: order.id).update_all(confirmed_by_id: other.id, confirmed_at: Time.current, state: "confirmed") }
    confirm(order)
    [ { total_minor: 1 }, { confirmed_at: 1.day.ago }, { confirmed_by_id: other.id }, { state: "draft" } ].each do |attributes|
      database_rejects { Order.where(id: order.id).update_all(attributes) }
    end
    database_rejects { OrderItem.where(id: order.order_items.sole.id).update_all(quantity: 99) }
    database_rejects { Order.where(id: order.id).delete_all }
    movement = order.order_items.sole.inventory_logs.sole
    database_rejects do
      InventoryLog.insert_all!([ movement.attributes.except("id").merge("operation_key" => SecureRandom.uuid,
        "order_item_id" => second_order.order_items.sole.id) ])
    end
    void(order)
    database_rejects { Order.where(id: order.id).update_all(void_reason: "Rewritten") }
    reconcile
  end

  private
    def draft(**options)
      Sales::Draft.call(business: @business, actor: @owner,
        lines: options.fetch(:lines, [ { product_id: @product.id, quantity: 3 } ]), submission_key: options.fetch(:submission_key, SecureRandom.uuid))
    end

    def confirm(order, **options)
      Sales::Confirm.call(business: @business, actor: @owner, order_id: order.id,
        revision: options.fetch(:revision, order.revision), review_token: options.fetch(:review_token, order.review_token))
    end

    def void(order, reason: "Entry mistake", acknowledged: "1")
      Sales::Void.call(business: @business, actor: @owner, order_id: order.id, reason: reason, acknowledged: acknowledged)
    end

    def database_rejects(&block)
      assert_raises(ActiveRecord::StatementInvalid) { Order.transaction(requires_new: true, &block) }
    end

    def reconcile
      @business.products.each { |product| assert_equal product.quantity, product.inventory_logs.sum(:quantity_delta) }
    end
end
