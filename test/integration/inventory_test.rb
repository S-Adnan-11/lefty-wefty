require "test_helper"

class InventoryTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_owner
    @other = create_owner(email: "other@example.test", name: "FOREIGN BUSINESS")
    @product = create_product(@owner.business)
    @foreign = create_product(@other.business, name: "FOREIGN PRODUCT", sku: "FOREIGN")
    change_stock(@foreign, 73)
  end

  test "all inventory requests require authentication" do
    [ products_path, product_path(@product), new_product_path, edit_product_path(@product) ].each do |path|
      get path
      assert_redirected_to new_session_path
    end
    post products_path, params: { product: product_attributes }
    assert_redirected_to new_session_path
    patch product_path(@product), params: { product: { name: "Changed" } }
    assert_redirected_to new_session_path
    post archive_product_path(@product)
    assert_redirected_to new_session_path
    assert_no_difference "InventoryLog.count" do
      post product_stock_movements_path(@product), params: movement_params
      assert_redirected_to new_session_path
    end
  end

  test "lists, history and aggregates belong only to the session business" do
    sign_in_as(@owner)
    get products_path, params: { business_id: @other.business.id }
    assert_response :success
    assert_select "a", text: @product.name
    assert_select "a", text: @foreign.name, count: 0
    get root_path, params: { business_id: @other.business.id }
    assert_select "h1", "Overview"
    assert_select ".business-name", @owner.business.name
    assert_select ".metrics strong", text: "1", count: 2
    assert_select ".metrics strong", text: "0", count: 1
    assert_select "a", text: @foreign.name, count: 0
    get product_path(@product)
    assert_select "#movement-history", count: 0
    assert_select "p", /No stock changes yet/
  end

  test "foreign record IDs cannot show edit update archive or receive nested movements" do
    sign_in_as(@owner)
    get product_path(@foreign)
    assert_response :not_found
    get edit_product_path(@foreign)
    assert_response :not_found
    patch product_path(@foreign), params: { product: { name: "Stolen", business_id: @owner.business.id } }
    assert_response :not_found
    post archive_product_path(@foreign)
    assert_response :not_found
    assert_no_difference "InventoryLog.count" do
      post product_stock_movements_path(@foreign), params: movement_params
      assert_response :not_found
    end
    assert_equal 73, @foreign.reload.quantity
    assert_nil @foreign.archived_at
    assert_equal "FOREIGN PRODUCT", @foreign.name
  end

  test "submitted ownership quantity and nested association fields cannot override server values" do
    sign_in_as(@owner)
    post products_path, params: {
      product: product_attributes.merge(business_id: @other.business.id, quantity: 900, archived_at: Time.current,
        inventory_logs_attributes: [ { business_id: @other.business.id, product_id: @foreign.id, quantity_delta: 90 } ]),
      opening_quantity: "0"
    }
    created = @owner.business.products.find_by!(sku: "NEW")
    assert_equal 0, created.quantity
    assert_nil created.archived_at
    patch product_path(created), params: { product: { name: "Edited", quantity: 900, business_id: @other.business.id } }
    assert_equal 0, created.reload.quantity
    assert_equal @owner.business.id, created.business_id
    post product_stock_movements_path(created), params: movement_params.merge(
      stock_change: movement_params[:stock_change].merge(product_id: @foreign.id, business_id: @other.business.id, actor_id: @other.id))
    movement = created.inventory_logs.sole
    assert_equal @owner.id, movement.actor_id
    assert_equal @owner.business.id, movement.business_id
    assert_equal 10, created.reload.quantity
    assert_equal 73, @foreign.reload.quantity
  end

  test "browser-shaped receipt retry adjustment rejection low stock and archive flow" do
    sign_in_as(@owner)
    submission = movement_params
    2.times do
      post product_stock_movements_path(@product), params: submission
      assert_redirected_to product_path(@product)
    end
    assert_equal 10, @product.reload.quantity
    assert_equal 1, @product.inventory_logs.count
    get product_path(@product)
    assert_select "#quantity", "10"
    assert_select "#movement-history tbody tr", count: 1
    post product_stock_movements_path(@product), params: movement_params(quantity: -2, kind: "adjustment", reason: "Two damaged")
    get products_path, params: { status: "low" }
    assert_select "a", text: @product.name
    assert_equal 8, @product.reload.quantity
    assert_no_difference "InventoryLog.count" do
      post product_stock_movements_path(@product), params: movement_params(quantity: -9, kind: "adjustment", reason: "Invalid correction")
      assert_response :unprocessable_entity
      assert_select "[role=alert]", /below zero/
    end
    assert_equal 8, @product.reload.quantity
    post archive_product_path(@product)
    follow_redirect!
    assert_select "h2", "Archived product"
    assert_select "form[action=?]", product_stock_movements_path(@product), count: 0
    get products_path, params: { status: "low" }
    assert_select "a", text: @product.name, count: 0
    post product_stock_movements_path(@product), params: movement_params(quantity: 1)
    assert_response :unprocessable_entity
    assert_equal 8, @product.reload.quantity
  end

  test "search escapes wildcards and pagination stays scoped" do
    sign_in_as(@owner)
    22.times { |i| create_product(@owner.business, sku: "PAGE-#{i}", name: "Page item #{i}") }
    get products_path
    assert_select "tbody tr", count: 20
    assert_select "nav[aria-label=Pagination]", /Page 1 of 2/
    get products_path, params: { page: 2 }
    assert_select "tbody tr", count: 3
    get products_path, params: { q: "%" }
    assert_select "tbody tr", count: 0
    get products_path, params: { q: "BOOK-1" }
    assert_select "tbody tr", count: 1
  end

  test "invalid numeric input and nonexistent balance mutation routes cannot change stock" do
    sign_in_as(@owner)
    assert_no_difference "Product.count" do
      post products_path, params: { product: product_attributes.merge(price_naira: "1.001") }
      assert_response :unprocessable_entity
    end
    patch product_path(@product), params: { product: { low_stock_threshold: Product::MAX_QUANTITY + 1 } }
    assert_response :unprocessable_entity
    patch product_path(@product), params: { product: { price_naira: "10000000000.00" } }
    assert_response :unprocessable_entity
    patch "/products/#{@product.id}/quantity", params: { quantity: 50 }
    assert_response :not_found
    patch "/products/#{@product.id}/stock_movements/1", params: { quantity_delta: 50 }
    assert_response :not_found
    assert_equal 0, @product.reload.quantity
  end

  private
    def product_attributes
      { name: "New product", sku: "NEW", price_naira: "5.00", low_stock_threshold: 0 }
    end

    def movement_params(quantity: 10, kind: "receipt", reason: nil)
      { stock_change: { kind: kind, quantity: quantity, reason: reason, operation_key: SecureRandom.uuid } }
    end
end
