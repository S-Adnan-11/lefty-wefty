require "test_helper"
require "timeout"

class ConcurrentSalesTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    raise "Sales races require the dedicated test database" unless ActiveRecord::Base.connection_db_config.database == "lefty_wefty_test"
    @owner = create_owner(email: "sale-race-#{SecureRandom.hex(8)}@example.test")
    @business = @owner.business
    @product = create_product(@business)
    change_stock(@product, 1)
  end

  teardown do
    ActiveRecord::Base.connection.execute("TRUNCATE inventory_logs, order_items, sale_submissions, orders, products, businesses, sessions, users CASCADE")
  end

  test "two sales for a final unit yield one confirmation and one usable draft" do
    orders = [ draft, draft ]
    results = race(@product, orders.map { |order| -> { confirm(order) } })
    assert_equal 1, results.count { |result| result.is_a?(Order) && result.confirmed? }
    assert_equal 1, results.count { |result| result.is_a?(Stock::Apply::Rejected) }
    assert_equal [ "confirmed", "draft" ], orders.map { |order| order.reload.state }.sort
    assert_equal 0, @product.reload.quantity
    assert_equal 1, @product.inventory_logs.where(kind: "sale").count
    reconcile
  end

  test "concurrent confirmations deduct once and return the same sale" do
    order = draft
    results = race(order, [ -> { confirm(order) }, -> { confirm(order) } ])
    assert results.all? { |result| result.is_a?(Order) && result.confirmed? }
    assert_equal 1, results.map(&:id).uniq.size
    assert_equal 0, @product.reload.quantity
    assert_equal 1, @product.inventory_logs.where(kind: "sale").count
    reconcile
  end

  test "concurrent voids restore once and preserve the original record" do
    order = confirm(draft)
    results = race(order, [ -> { void(order) }, -> { void(order) } ])
    assert results.all? { |result| result.is_a?(Order) && result.voided? }
    assert_equal 1, results.map(&:voided_at).uniq.size
    assert_equal "Entry mistake", order.reload.void_reason
    assert_equal 1, @product.reload.quantity
    assert_equal 1, @product.inventory_logs.where(kind: "sale_void").count
    reconcile
  end

  test "conflicting concurrent voids preserve whichever reason commits first" do
    order = confirm(draft)
    results = race(order, [ -> { void(order, "Reason A") }, -> { void(order, "Reason B") } ])
    assert_equal 1, results.count { |result| result.is_a?(Order) }
    assert_equal 1, results.count { |result| result.is_a?(Sales::Rejected) }
    assert_equal results.find { |result| result.is_a?(Order) }.void_reason, order.reload.void_reason
    assert_equal 1, @product.reload.quantity
    reconcile
  end

  test "confirmation and existing adjustment contend safely for the final unit" do
    order = draft
    results = race(@product, [ -> { confirm(order) }, -> { change_stock(@product, -1, kind: "adjustment", reason: "Count correction") } ])
    assert_equal 1, results.count { |result| result.is_a?(Stock::Apply::Rejected) }
    assert_equal 0, @product.reload.quantity
    assert_equal 2, @product.inventory_logs.count
    reconcile
  end

  test "receipt and sale both succeed without losing a balance update" do
    order = draft
    results = race(@product, [ -> { confirm(order) }, -> { change_stock(@product, 4) } ])
    assert results.none? { |result| result.is_a?(Exception) }
    assert_equal 4, @product.reload.quantity
    assert order.reload.confirmed?
    reconcile
  end

  test "confirm and void serialize to confirmed or voided without partial effects" do
    order = draft
    results = race(order, [ -> { confirm(order) }, -> { void(order) } ])
    assert results.any? { |result| result.is_a?(Order) }
    assert_includes %w[confirmed voided], order.reload.state
    assert_equal 1, @product.inventory_logs.where(kind: "sale").count
    assert_equal order.voided? ? 1 : 0, @product.inventory_logs.where(kind: "sale_void").count
    assert_equal order.voided? ? 1 : 0, @product.reload.quantity
    assert confirm(order).state == order.state
    reconcile
  end

  test "same draft creation identity races to one order and conflicts stay explicit" do
    key = SecureRandom.uuid
    results = race(@business, [ -> { draft(key: key) }, -> { draft(key: key) } ])
    assert_equal 1, results.map(&:id).uniq.size
    assert_equal 1, @business.orders.count
    assert_equal 1, @business.sale_submissions.count
    assert_equal 1, @product.reload.quantity
    reconcile
  end

  test "opposite input order on multiple products finishes with consistent lock order" do
    second = create_product(@business, sku: "SECOND")
    change_stock(second, 1)
    lines = [ { product_id: @product.id, quantity: 1 }, { product_id: second.id, quantity: 1 } ]
    orders = [ draft(lines: lines), draft(lines: lines.reverse) ]
    results = race(@product, orders.map { |order| -> { confirm(order) } })
    assert_equal 1, results.count { |result| result.is_a?(Order) }
    assert_equal 1, results.count { |result| result.is_a?(Stock::Apply::Rejected) }
    assert_equal [ 0, 0 ], [ @product.reload.quantity, second.reload.quantity ]
    reconcile
  end

  test "editing and confirming cannot silently use an unreviewed draft" do
    order = draft
    results = race(order, [ -> { confirm(order) }, -> {
      Sales::Draft.call(business: @business, actor: @owner, order_id: order.id, revision: order.revision,
        lines: [ { product_id: @product.id, quantity: 2 } ])
    } ])
    assert_equal 1, results.count { |result| result.is_a?(Order) }
    assert_equal 1, results.count { |result| result.is_a?(Sales::Rejected) }
    if order.reload.draft?
      assert_equal 2, order.order_items.sole.quantity
      assert_equal 1, @product.reload.quantity
    else
      assert_equal 1, order.order_items.sole.quantity
      assert_equal 0, @product.reload.quantity
    end
    reconcile
  end

  private
    def draft(key: SecureRandom.uuid, lines: [ { product_id: @product.id, quantity: 1 } ])
      Sales::Draft.call(business: @business, actor: @owner, submission_key: key, lines: lines)
    end

    def confirm(order)
      Sales::Confirm.call(business: @business, actor: @owner, order_id: order.id,
        revision: order.revision, review_token: order.review_token)
    end

    def void(order, reason = "Entry mistake")
      Sales::Void.call(business: @business, actor: @owner, order_id: order.id, reason: reason, acknowledged: "1")
    end

    def reconcile
      @business.products.each { |product| assert_equal product.quantity, product.inventory_logs.sum(:quantity_delta) }
    end

    def race(record, actions)
      ready, start, outcomes, pids = Queue.new, Queue.new, Queue.new, Queue.new
      workers = []
      record.with_lock do
        workers = actions.map do |action|
          Thread.new do
            Thread.current.report_on_exception = false
            ActiveRecord::Base.connection_pool.with_connection do |connection|
              connection.execute("SET lock_timeout = '8s'")
              pids << connection.select_value("SELECT pg_backend_pid()").to_i
              ready << true
              start.pop
              begin
                outcomes << action.call
              rescue StandardError => error
                outcomes << error
              ensure
                connection.execute("RESET lock_timeout")
              end
            end
          end
        end
        Timeout.timeout(10) { actions.size.times { ready.pop } }
        worker_pids = actions.map { pids.pop }
        assert_equal actions.size, worker_pids.uniq.size
        actions.size.times { start << true }
        Timeout.timeout(10) do
          loop do
            waiting = ActiveRecord::Base.uncached do
              connection = ActiveRecord::Base.connection
              connection.execute("SELECT pg_stat_clear_snapshot()")
              connection.select_value("SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{worker_pids.join(',')}) AND wait_event_type = 'Lock'").to_i
            end
            break if waiting == actions.size
            Thread.pass
          end
        end
      end
      Timeout.timeout(20) { workers.each(&:value) }
      actions.map { outcomes.pop }
    ensure
      workers&.each { |worker| worker.kill if worker.alive? }
      workers&.each(&:join)
    end
end
