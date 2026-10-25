require "test_helper"
require "timeout"

class StockUpdatesTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    raise "Concurrent test requires the dedicated test database" unless ActiveRecord::Base.connection_db_config.database == "lefty_wefty_test"
    @owner = create_owner(email: "race-#{SecureRandom.hex(8)}@example.test")
    @product = create_product(@owner.business)
  end

  teardown do
    # This class commits data to exercise independent PostgreSQL transactions.
    # Other tests use rollback; truncation is limited to this dedicated test DB.
    ActiveRecord::Base.connection.execute("TRUNCATE inventory_logs, products, businesses, sessions, users CASCADE")
  end

  test "independent connections serialize receipts without losing units" do
    results, pids = race([ 7, 11 ]) { |quantity| change_stock(@product, quantity) }
    assert_equal 2, pids.uniq.size
    assert results.all? { |result| result.is_a?(InventoryLog) }
    assert_equal 18, @product.reload.quantity
    assert_equal 18, @product.inventory_logs.sum(:quantity_delta)
    assert_equal 18, @product.inventory_logs.order(:id).last.resulting_balance
  end

  test "racing the same receipt produces exactly one movement" do
    key = SecureRandom.uuid
    results, pids = race([ 10, 10 ]) { |quantity| change_stock(@product, quantity, key: key) }
    assert_equal 2, pids.uniq.size
    assert_equal 1, results.map(&:id).uniq.size
    assert_equal 1, @product.inventory_logs.count
    assert_equal 10, @product.reload.quantity
  end

  test "two corrections for the last unit cannot make stock negative" do
    change_stock(@product, 1)
    results, pids = race([ -1, -1 ]) { |quantity| change_stock(@product, quantity, kind: "adjustment", reason: "Count correction") }
    assert_equal 2, pids.uniq.size
    assert_equal 1, results.count { |result| result.is_a?(InventoryLog) }
    assert_equal 1, results.count { |result| result.is_a?(Stock::Apply::Rejected) }
    assert_equal 0, @product.reload.quantity
    assert_equal 0, @product.inventory_logs.sum(:quantity_delta)
  end

  private
    def race(quantities)
      ready, start, outcomes, backend_pids = Queue.new, Queue.new, Queue.new, Queue.new
      # Hold the row until both worker connections are ready to contend for it.
      workers = []
      @product.with_lock do
        workers = quantities.map do |quantity|
          Thread.new do
            Thread.current.report_on_exception = false
            ActiveRecord::Base.connection_pool.with_connection do |connection|
              connection.execute("SET lock_timeout = '8s'")
              backend_pids << connection.select_value("SELECT pg_backend_pid()")
              ready << true
              start.pop
              begin
                outcomes << yield(quantity)
              rescue Stock::Apply::Rejected => error
                outcomes << error
              end
            ensure
              connection.execute("RESET lock_timeout")
            end
          end
        end
        Timeout.timeout(10) { quantities.size.times { ready.pop } }
        quantities.size.times { start << true }
        Timeout.timeout(10) do
          loop do
            waiting = ActiveRecord::Base.uncached do
              connection = ActiveRecord::Base.connection
              connection.execute("SELECT pg_stat_clear_snapshot()")
              connection.select_value("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'").to_i
            end
            break if waiting >= quantities.size
            sleep 0.01
          end
        end
      end
      Timeout.timeout(15) { workers.each(&:value) }
      [ quantities.map { outcomes.pop }, quantities.map { backend_pids.pop } ]
    ensure
      workers&.each { |worker| worker.kill if worker.alive? }
      workers&.each(&:join)
    end
end
