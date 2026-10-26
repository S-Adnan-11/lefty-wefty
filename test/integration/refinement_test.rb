require "test_helper"

class RefinementTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_owner
    @other = create_owner(email: "other@example.test")
    @product = create_product(@owner.business)
    sign_in_as(@owner)
  end

  test "naira product create edit invalid input and crafted minor values" do
    assert_difference "Product.count" do
      post products_path, params: { product: { name: "Rice", sku: "", price_naira: " 1,250.50 ", price_minor: 1, low_stock_threshold: 0 }, opening_quantity: "7" }
    end
    product = @owner.business.products.order(:id).last
    assert_match(/\ALW-[A-F0-9]{8}\z/, product.sku)
    assert_equal 125050, product.price_minor
    assert_equal 7, product.quantity
    assert_equal 7, product.inventory_logs.sole.quantity_delta
    code = product.sku
    patch product_path(product), params: { product: { sku: " ", price_naira: "1250.501" } }
    assert_response :unprocessable_entity
    assert_select "input[name='product[price_naira]'][value='1250.501']"
    assert_select "#product_price_naira[aria-invalid=true][aria-describedby~='product-errors']"
    assert_select "input[name='product[price_minor]']", count: 0
    assert_equal 125050, product.reload.price_minor
    patch product_path(product), params: { product: { sku: " ", price_naira: "1250.5", quantity: 999 } }
    assert_response :redirect
    assert_equal code, product.reload.sku
    assert_equal 7, product.quantity
    get edit_product_path(product)
    assert_select "input[name='product[price_naira]'][value='1250.50']"
  end

  test "positive correction quantities translate to signed existing stock service and retry safely" do
    change_stock(@product, 10)
    payload = { stock_change: { kind: "adjustment", direction: "remove", quantity: "2", reason: "Damaged", operation_key: SecureRandom.uuid } }
    2.times do
      post product_stock_movements_path(@product), params: payload
      assert_response :redirect
    end
    assert_equal 8, @product.reload.quantity
    assert_equal(-2, @product.inventory_logs.order(:id).last.quantity_delta)
    [ "-2", "0", "2.5", "1e2" ].each do |quantity|
      assert_no_difference "InventoryLog.count" do
        post product_stock_movements_path(@product), params: { stock_change: payload[:stock_change].merge(quantity: quantity, operation_key: SecureRandom.uuid) }
        assert_response :unprocessable_entity
      end
    end
    assert_equal 8, @product.reload.quantity
  end

  test "password changes require current password confirmation and rotate all sessions" do
    stale_session = @owner.sessions.create!
    original_sessions = @owner.sessions.pluck(:id)
    reset_token = @owner.password_reset_token
    patch account_path, params: { user: { current_password: "wrong", password: "a new owner passphrase", password_confirmation: "a new owner passphrase" } }
    assert_response :unprocessable_entity
    assert_equal original_sessions.sort, @owner.sessions.pluck(:id).sort
    assert @owner.reload.authenticate("test owner passphrase")
    [ [ "short", "short" ], [ "a new owner passphrase", "different passphrase" ], [ "a new owner passphrase", "" ] ].each do |password, confirmation|
      patch account_path, params: { user: { current_password: "test owner passphrase", password: password, password_confirmation: confirmation } }
      assert_response :unprocessable_entity
      assert @owner.reload.authenticate("test owner passphrase")
    end
    foreign_digest = @other.password_digest
    patch account_path, params: { user: { id: @other.id, email_address: "forged@example.test", current_password: "test owner passphrase", password: "a new owner passphrase", password_confirmation: "a new owner passphrase" } }
    assert_redirected_to account_path
    assert @owner.reload.authenticate("a new owner passphrase")
    assert_equal "owner@example.test", @owner.email_address
    assert_equal foreign_digest, @other.reload.password_digest
    assert_equal 1, @owner.sessions.count
    assert_empty original_sessions & @owner.sessions.pluck(:id)
    assert_nil Session.find_by(id: stale_session.id)
    assert_nil User.find_by_password_reset_token(reset_token)
    follow_redirect!
    assert_select "h1", "My account"
    assert_select "input[type=password][value]", count: 0
  end

  test "right aligned navigation retains all destinations and native no script help" do
    get new_product_path
    assert_select "nav[aria-label='Main navigation'] a", text: /Overview|Products|Sales|Stock history|Reports/, count: 5
    assert_select "a[aria-current=page]", text: "Products"
    assert_select "details[data-help] summary", count: 3
    assert_select "details[data-menu] form input[name=_method][value=delete]"
    get report_path
    assert_select "#monthly-sales tbody tr", count: 1
    assert_select "nav[aria-label='Report range'] a", text: "Last 3 months"
    get report_path, params: { first_month: "2020-01", last_month: "2026-10" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /Choose 36 months or fewer/
  end
end
