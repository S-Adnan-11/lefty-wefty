require "test_helper"
require_relative "../test_helpers/reporting_test_helper"

class ReportingTest < ActionDispatch::IntegrationTest
  include ReportingTestHelper
  setup do
    @owner = create_owner
    @other = create_owner(email: "foreign-interface@example.test", name: "FOREIGN REPORT BUSINESS")
    @product = reporting_stock(@owner.business, sku: "OWN")
    @foreign = reporting_stock(@other.business, sku: "FOREIGN-ONLY", price: 999999)
    @sale = recorded_sale(@owner.business, at: Time.current, lines: { @product => 2 })
    @foreign_sale = recorded_sale(@other.business, at: Time.current, lines: { @foreign => 3 })
  end

  test "report and movements require login and crafted ownership never changes the session scope" do
    [ report_path, stock_movements_path ].each do |path|
      get path
      assert_redirected_to new_session_path
    end
    sign_in_as(@owner)
    get report_path, params: { business_id: @other.business.id, owner_id: @other.id }
    assert_response :success
    assert_select "#monthly-sales tfoot td", text: "NGN 50.00"
    assert_select "#monthly-sales tbody tr", count: 12
    get stock_movements_path, params: { business_id: @other.business.id }
    assert_response :success
    assert_select "td", text: /FOREIGN-ONLY/, count: 0
    get stock_movements_path, params: { product_id: @foreign.id }
    assert_response :not_found
    get orders_path, params: { reference: "##{@foreign_sale.id}", business_id: @other.business.id }
    assert_select "tbody tr", count: 0
    get report_path, params: { first_month: "2025-01'; DROP TABLE orders;--", last_month: "2025-03" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /YYYY-MM/
    assert Order.exists?(@sale.id)
  end

  test "dashboard and report agree after void and active low stock summaries use all products" do
    sign_in_as(@owner)
    22.times { |i| create_product(@owner.business, name: "Zero #{i}", sku: "ZERO-#{i}", low_stock_threshold: 0) }
    archived = create_product(@owner.business, sku: "ARCHIVED", archived_at: Time.current)
    assert archived.archived?
    get root_path
    assert_response :success
    assert_select "#month-sale-count", "1"
    assert_select "#month-sales-value", "NGN 50.00"
    assert_select ".metrics strong", text: "23"
    assert_select ".metrics strong", text: "22"
    assert_select "a", text: "Sale ##{@sale.id}"
    assert_select "a", text: "Sale ##{@foreign_sale.id}", count: 0
    void_sale(@sale, at: Time.current + 1.second)
    get root_path
    assert_select "#month-sale-count", "0"
    assert_select "#month-sales-value", "NGN 0.00"
    get report_path
    assert_select "tfoot td", text: "NGN 0.00"
  end

  test "filter pagination uses stable ordering keeps GET state and handles invalid pages and sorts" do
    sign_in_as(@owner)
    22.times { |i| create_product(@owner.business, name: "Same name", sku: "MATCH-#{i}") }
    get products_path, params: { q: "MATCH", status: "low", page: "1", sort: "name;DROP TABLE users" }
    assert_response :success
    first = css_select("tbody tr td:first-child a").map { |node| node["href"] }
    assert_equal 20, first.size
    assert_select "a[href*='page=2'][href*='q=MATCH'][href*='status=low']", text: "Next"
    get products_path, params: { q: "MATCH", status: "low", page: "2" }
    second = css_select("tbody tr td:first-child a").map { |node| node["href"] }
    assert_equal 2, second.size
    assert_empty first & second
    [ "-1", "1garbage", "1;DROP TABLE users", "999999999999999999999" ].each do |page|
      get products_path, params: { q: "MATCH", page: page }
      assert_select "tbody tr", count: 20
    end
    get products_path, params: { q: "MATCH", page: "999" }
    assert_select "tbody tr", count: 2
    get products_path, params: { q: "%' OR 1=1--" }
    assert_select "tbody tr", count: 0
    get orders_path, params: { reference: "##{@sale.id}", status: "confirmed" }
    assert_select "tbody tr", count: 1
    get orders_path, params: { reference: "1 OR 1=1" }
    assert_select "tbody tr", count: 0
    22.times do
      Sales::Draft.call(business: @owner.business, actor: @owner, submission_key: SecureRandom.uuid,
        lines: [ { product_id: @product.id, quantity: 1 } ])
    end
    get orders_path, params: { status: "draft" }
    sale_page = css_select("tbody tr td:first-child a").map { |node| node["href"] }
    assert_equal 20, sale_page.size
    assert_select "a[href*='status=draft'][href*='page=2']", text: "Next"
    get orders_path, params: { status: "draft", page: 2 }
    assert_select "tbody tr", count: 2
    assert_empty sale_page & css_select("tbody tr td:first-child a").map { |node| node["href"] }
    get stock_movements_path, params: { product_id: "#{@product.id} OR 1=1" }
    assert_response :not_found
    23.times { change_stock(@product, 1) }
    get stock_movements_path, params: { product_id: @product.id, kind: "receipt" }
    assert_select "#stock-movements tbody tr", count: 20
    assert_select "a[href*='kind=receipt'][href*='page=2']", text: "Next"
    get stock_movements_path, params: { product_id: @product.id, kind: "receipt", page: 2 }
    assert_select "#stock-movements tbody tr", count: 4
  end

  test "report renders aggregate money beyond bigint exactly" do
    product = reporting_stock(@owner.business, sku: "LARGE", price: 999_999_999_999, quantity: 20_000_000)
    2.times { recorded_sale(@owner.business, at: Time.utc(2024, 2, 10), lines: { product => 9_007_200 }) }
    sign_in_as(@owner)
    get report_path, params: { first_month: "2024-02", last_month: "2024-02" }
    assert_response :success
    assert_select "tfoot td", text: "NGN 180,143,999,999,819,856.00"
    assert_select "tfoot td", text: "18,014,400"
  end
end
