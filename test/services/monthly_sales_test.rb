require "test_helper"
require_relative "../test_helpers/reporting_test_helper"

class MonthlySalesTest < ActiveSupport::TestCase
  include ReportingTestHelper
  setup do
    @owner = create_owner
    @business = @owner.business
    @a = reporting_stock(@business, sku: "A", price: 2500)
    @b = reporting_stock(@business, sku: "B", price: 5000)
    @c = reporting_stock(@business, sku: "C", price: 10000)
  end

  test "independent equal-value multi-item arithmetic excludes drafts voids and foreign sales and preserves history" do
    # 2*2500 + 1*5000 = 10000, then 1*10000 = 10000: 2 sales, 4 units, 20000.
    recorded_sale(@business, at: Time.utc(2025, 1, 10), lines: { @a => 2, @b => 1 })
    recorded_sale(@business, at: Time.utc(2025, 1, 11), lines: { @c => 1 })
    discarded = recorded_sale(@business, at: Time.utc(2025, 1, 12), lines: { @c => 2 })
    void_sale(discarded)
    Sales::Draft.call(business: @business, actor: @owner, submission_key: SecureRandom.uuid,
      lines: [ { product_id: @a.id, quantity: 10 } ])
    other = create_owner(email: "foreign-report@example.test")
    foreign = reporting_stock(other.business, sku: "FOREIGN", price: 999999)
    recorded_sale(other.business, at: Time.utc(2025, 1, 11), lines: { foreign => 90 })
    @a.update!(name: "New name", price_minor: 1, archived_at: Time.current)
    result = report
    assert_equal [ [ 2025, 1 ], [ 2025, 2 ], [ 2025, 3 ] ], result.rows.map { |r| [ r.month.year, r.month.month ] }
    assert_equal [ [ 2, 4, 20000 ], [ 0, 0, 0 ], [ 0, 0, 0 ] ], result.rows.map { |r| [ r.sale_count, r.units, r.total_minor ] }
    assert_equal [ 2, 4, 20000 ], [ result.sale_count, result.units, result.total_minor ]
    assert_raises(Sales::Rejected) { Reports::MonthlySales.call(business: @business, actor: other) }
  end

  test "later void removes only the original confirmation month with a fresh read" do
    order = recorded_sale(@business, at: Time.utc(2025, 1, 15), lines: { @a => 2 })
    assert_equal 5000, report.total_minor
    void_sale(order)
    assert_equal [ 0, 0, 0 ], report.rows.map(&:total_minor)
  end

  test "Lagos local half-open boundaries leap day and UTC disagreement ignore database session zone" do
    [ Time.utc(2024, 1, 31, 22, 59, 59), Time.utc(2024, 1, 31, 23),
      Time.utc(2024, 2, 29, 22, 59, 59), Time.utc(2024, 2, 29, 23), Time.utc(2024, 2, 29, 23, 30) ].each do |time|
      recorded_sale(@business, at: time, lines: { @a => 1 })
    end
    connection = ActiveRecord::Base.connection
    original = connection.select_value("SHOW TIMEZONE")
    begin
      connection.execute("SET TIME ZONE 'America/New_York'")
      february = report(first_month: "2024-02", last_month: "2024-02")
      assert_equal [ 2, 2, 5000 ], [ february.sale_count, february.units, february.total_minor ]
      march = report(first_month: "2024-03", last_month: "2024-03")
      assert_equal 2, march.sale_count
      connection.execute("SET TIME ZONE 'UTC'")
      assert_equal february.rows, report(first_month: "2024-02", last_month: "2024-02").rows
    ensure
      connection.execute("SET TIME ZONE #{connection.quote(original)}")
    end
  end

  test "year transition defaults zero months strict ranges and one reference clock" do
    result = Reports::MonthlySales.call(business: @business, actor: @owner, now: Time.utc(2024, 12, 31, 23, 30))
    assert_equal Date.new(2024, 2, 1), result.first_month
    assert_equal Date.new(2025, 1, 1), result.last_month
    assert_equal 12, result.rows.size
    assert_equal 0, result.sale_count
    recorded_sale(@business, at: Time.utc(2024, 12, 31, 23, 30), lines: { @a => 1 })
    assert_equal 1, report(first_month: "2025-01", last_month: "2025-01").sale_count
    [ "2025-00", "2025-13", "2025-1", "0000-01", "2025-02-01", "2025-01' OR 1=1--", "", [ "2025-01" ] ].each do |value|
      assert_raises(Reports::MonthlySales::InvalidRange) { report(first_month: value) }
    end
    assert_raises(Reports::MonthlySales::InvalidRange) { report(first_month: "2025-04") }
    assert_raises(Reports::MonthlySales::InvalidRange) { report(first_month: "2022-03", last_month: "2025-03") }
    assert_equal 36, report(first_month: "2022-04", last_month: "2025-03").rows.size
    empty = create_owner(email: "empty-report@example.test")
    assert_equal 0, Reports::MonthlySales.call(business: empty.business, actor: empty).total_minor
  end

  test "aggregate amounts exceed bigint and floating-point precision without loss and reports are read only" do
    huge = reporting_stock(@business, sku: "HUGE", price: 999_999_999_999, quantity: 20_000_000)
    2.times { recorded_sale(@business, at: Time.utc(2025, 1, 20), lines: { huge => 9_007_200 }) }
    expected = 2 * 9_007_200 * 999_999_999_999
    assert_operator expected, :>, Order::MAX_AMOUNT
    before = [ Order, OrderItem, Product, InventoryLog ].map { |model| model.order(:id).map(&:attributes) }
    assert_equal expected, report.total_minor
    assert_instance_of Integer, report.total_minor
    assert_equal before, [ Order, OrderItem, Product, InventoryLog ].map { |model| model.order(:id).map(&:attributes) }
  end

  test "SQL uses one bounded select with real binds and can be explained on PostgreSQL" do
    30.times { recorded_sale(@business, at: Time.utc(2025, 1, 20), lines: { @a => 1, @b => 1 }) }
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) { queries << payload if payload[:name] == "Monthly sales" }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { report }
    assert_equal 1, queries.size
    assert_equal [ @business.id, "2025-01-01", "2025-03-01", "Africa/Lagos" ], queries.sole[:binds].map(&:value_for_database)
    plan = ActiveRecord::Base.connection.select_all("EXPLAIN (ANALYZE, BUFFERS) #{Reports::MonthlySales::SQL}", "Report plan", queries.sole[:binds])
    assert plan.rows.flatten.any? { |line| line.include?("Execution Time") }
    puts "REPORT QUERY PLAN\n#{plan.rows.flatten.join("\n")}"
  end

  private
    def report(**options)
      Reports::MonthlySales.call(business: @business, actor: @owner, first_month: "2025-01", last_month: "2025-03", **options)
    end
end
