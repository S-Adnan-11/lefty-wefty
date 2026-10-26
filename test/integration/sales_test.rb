require "test_helper"

class SalesRequestsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_owner
    @other = create_owner(email: "other@example.test")
    @product = create_product(@owner.business)
    @foreign_product = create_product(@other.business, name: "Foreign catalogue item")
    change_stock(@product, 10)
    @order = make_draft(@owner, @product)
    @foreign = make_draft(@other, @foreign_product)
  end

  test "all sale routes require authentication" do
    [ orders_path, new_order_path, order_path(@order), edit_order_path(@order) ].each do |path|
      get path
      assert_redirected_to new_session_path
    end
    [ [ :post, orders_path ], [ :patch, order_path(@order) ], [ :delete, order_path(@order) ],
      [ :post, confirm_order_path(@order) ], [ :post, void_order_path(@order) ] ].each do |method, path|
      public_send(method, path)
      assert_redirected_to new_session_path
    end
    assert_equal 10, @product.reload.quantity
  end

  test "foreign sale IDs cannot read edit discard confirm or void" do
    sign_in_as(@owner)
    [ order_path(@foreign), edit_order_path(@foreign) ].each do |path|
      get path
      assert_response :not_found
    end
    [ [ :patch, order_path(@foreign) ], [ :delete, order_path(@foreign) ],
      [ :post, confirm_order_path(@foreign) ], [ :post, void_order_path(@foreign) ] ].each do |method, path|
      public_send(method, path, params: payload)
      assert_response :not_found
    end
    get orders_path, params: { business_id: @other.business.id }
    assert_select "a", text: "Sale ##{@order.id}"
    assert_select "a", text: "Sale ##{@foreign.id}", count: 0
    assert @foreign.reload.draft?
    assert_no_difference "Order.count" do
      post orders_path, params: payload(lines: [ { product_id: @foreign_product.id, quantity: 1 } ])
      assert_response :unprocessable_entity
    end
    assert_no_difference "OrderItem.count" do
      patch order_path(@order), params: payload(lines: [ { product_id: @foreign_product.id, quantity: 1 } ])
      assert_response :unprocessable_entity
    end
    assert_equal 10, @product.reload.quantity
  end

  test "review confirm history and void ignore forged prices totals and owners" do
    sign_in_as(@owner)
    request = payload
    2.times do
      post orders_path, params: request
      assert_response :see_other
    end
    created = @owner.business.orders.find_by!(submission_key: request[:order][:submission_key])
    assert_equal 2, @owner.business.orders.count
    assert_equal 375000, created.total_minor
    assert_equal 10, @product.reload.quantity
    get order_path(created)
    assert_select "h2", "Review draft"
    assert_select "#sale-total", "₦3,750.00"
    assert_select "input[name=revision][value=?]", created.revision.to_s
    2.times do
      post confirm_order_path(created), params: { revision: created.revision, review_token: created.review_token,
        total_minor: 1, actor_id: @other.id, business_id: @other.business.id, lines: [ { quantity: 99 } ] }
      assert_redirected_to order_path(created)
    end
    created.reload
    assert_equal @owner.id, created.confirmed_by_id
    assert_equal 375000, created.total_minor
    assert_equal 7, @product.reload.quantity
    get order_path(created)
    assert_select "h2", "Recorded sale"
    assert_select "a", text: "Product stock history"
    get product_path(@product)
    assert_select "a[href=?]", order_path(created), text: "Sale ##{created.id}"
    2.times do
      post void_order_path(created), params: { void_reason: "Wrong entry", acknowledged: "1", actor_id: @other.id }
      assert_redirected_to order_path(created)
    end
    assert_equal 10, @product.reload.quantity
    assert_equal @owner.id, created.reload.voided_by_id
    get order_path(created)
    assert_select "h2", "Sale cancelled"
    assert_select "form[action=?]", void_order_path(created), count: 0
    post void_order_path(created), params: { void_reason: "Changed reason", acknowledged: "1" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /different reason/
    assert_equal "Wrong entry", created.reload.void_reason
    post confirm_order_path(created), params: { revision: -1, review_token: "old" }
    follow_redirect!
    assert_select "[role=status]", /cancelled/
  end

  test "stale quote and stale edit recover with the saved server review" do
    sign_in_as(@owner)
    original_revision = @order.revision
    original_token = @order.review_token
    @product.update!(price_minor: 140000)
    post confirm_order_path(@order), params: { revision: original_revision, review_token: original_token, total_minor: 1 }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /Prices or product details changed/
    assert_select "#sale-total", "₦4,200.00"
    assert_equal 10, @product.reload.quantity
    assert @order.reload.draft?
    patch order_path(@order), params: payload(revision: original_revision)
    follow_redirect!
    assert_select "[role=alert]", /changed after your review/
    post confirm_order_path(@order), params: { revision: @order.revision, review_token: @order.review_token }
    assert_redirected_to order_path(@order)
    assert_equal 420000, @order.reload.total_minor
    assert_equal 7, @product.reload.quantity
  end

  test "insufficient stock invalid lines void draft and recorded edit have useful errors" do
    sign_in_as(@owner)
    post orders_path, params: payload(lines: [ { product_id: @product.id, quantity: "1.5" } ])
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /positive whole quantity/
    patch order_path(@order), params: payload(lines: [ { product_id: @product.id, quantity: 11 } ])
    assert_response :see_other
    @order.reload
    post confirm_order_path(@order), params: { revision: @order.revision, review_token: @order.review_token }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /Insufficient stock/
    assert_select "a", text: "Edit draft"
    post void_order_path(@order), params: { void_reason: "Wrong", acknowledged: "1" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /Only a completed sale/
    patch order_path(@order), params: payload(lines: [ { product_id: @product.id, quantity: 3 } ])
    @order.reload
    post confirm_order_path(@order), params: { revision: @order.revision, review_token: @order.review_token }
    get edit_order_path(@order)
    assert_redirected_to order_path(@order)
    patch order_path(@order), params: payload
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /Only drafts/
    delete order_path(@order), params: { revision: @order.revision }
    assert_redirected_to order_path(@order)
    assert @order.reload.confirmed?
  end

  test "sale pagination and status filters stay in the session business" do
    sign_in_as(@owner)
    20.times { make_draft(@owner, @product) }
    get orders_path
    assert_select "tbody tr", count: 20
    assert_select "nav[aria-label=Pagination]", /Page 1 of 2/
    get orders_path, params: { page: 2 }
    assert_select "tbody tr", count: 1
    get orders_path, params: { status: "confirmed", business_id: @other.business.id }
    assert_select "tbody tr", count: 0
  end

  test "a stock write failure shows a recoverable error and leaves the original draft untouched" do
    sign_in_as(@owner)
    Product.connection.execute <<~SQL
      CREATE FUNCTION reject_sale_request_balance() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'forced request write failure'; END; $$;
      CREATE TRIGGER reject_sale_request_balance BEFORE UPDATE OF quantity ON products
        FOR EACH ROW EXECUTE FUNCTION reject_sale_request_balance();
    SQL
    assert_no_difference "InventoryLog.count" do
      post confirm_order_path(@order), params: { revision: @order.revision, review_token: @order.review_token }
      assert_response :unprocessable_entity
      assert_select "[role=alert]", /No sale changes were saved/
      assert_select "a", text: "Edit draft"
    end
    assert @order.reload.draft?
    assert_nil @order.confirmed_at
    assert_nil @order.order_items.sole.unit_price_minor
    assert_equal 10, @product.reload.quantity
  end

  test "service tenant checks include foreign order IDs and actors" do
    assert_raises(ActiveRecord::RecordNotFound) do
      Sales::Confirm.call(business: @owner.business, actor: @owner, order_id: @foreign.id, revision: @foreign.revision, review_token: @foreign.review_token)
    end
    assert_raises(ActiveRecord::RecordNotFound) do
      Sales::Void.call(business: @owner.business, actor: @owner, order_id: @foreign.id, reason: "Wrong", acknowledged: "1")
    end
    assert_raises(Sales::Rejected) do
      Sales::Confirm.call(business: @owner.business, actor: @other, order_id: @order.id, revision: @order.revision, review_token: @order.review_token)
    end
    assert_raises(Sales::Rejected) do
      Sales::Void.call(business: @owner.business, actor: @other, order_id: @order.id, reason: "Wrong", acknowledged: "1")
    end
  end

  private
    def make_draft(owner, product)
      Sales::Draft.call(business: owner.business, actor: owner, submission_key: SecureRandom.uuid,
        lines: [ { product_id: product.id, quantity: 3 } ])
    end

    def payload(lines: [ { product_id: @product.id, quantity: 3 } ], revision: @order.revision)
      { order: { submission_key: SecureRandom.uuid, revision: revision, lines: lines,
        total_minor: 1, state: "confirmed", business_id: @other.business.id, confirmed_by_id: @other.id,
        items: [ { product_id: @foreign_product.id, unit_price_minor: 1 } ] } }
    end
end
