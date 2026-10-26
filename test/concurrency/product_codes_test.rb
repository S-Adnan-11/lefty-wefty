require "test_helper"
require "timeout"

class ProductCodeConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup { @owner = create_owner(email: "code-race-#{SecureRandom.hex(6)}@example.test") }
  teardown { ActiveRecord::Base.connection.execute("TRUNCATE inventory_logs, products, businesses, sessions, users CASCADE") }

  test "generated code collision on independent connections retries the database constraint safely" do
    ready, start, outcomes, pids = Queue.new, Queue.new, Queue.new, Queue.new
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.execute("SET lock_timeout = '8s'")
          pids << connection.select_value("SELECT pg_backend_pid()")
          actor = User.find(@owner.id)
          product = actor.business.products.new(name: "Race product", price_minor: 125050, low_stock_threshold: 0)
          product.define_singleton_method(:generate_code) do
            self.sku = "LW-COLLISION" if sku.blank?
          end
          original = product.method(:save!)
          attempts = 0
          product.define_singleton_method(:save!) do
            attempts += 1
            if attempts == 1
              valid = valid?
              raise "Expected valid pre-race code" unless valid
              ready << true
              start.pop
              # Both independent validations finished before either insert.
              original.call(validate: false)
            else
              self.sku = "LW-#{SecureRandom.hex(4).upcase}"
              original.call
            end
          end
          saved = Products::Create.call(product: product, actor: actor, opening_quantity: 3)
          outcomes << [ saved, product.id, attempts ]
        ensure
          connection.execute("RESET lock_timeout")
        end
      end
    end
    Timeout.timeout(10) { 2.times { ready.pop } }
    2.times { start << true }
    Timeout.timeout(15) { workers.each(&:value) }
    results = 2.times.map { outcomes.pop }
    assert_equal 2, 2.times.map { pids.pop }.uniq.size
    assert results.all?(&:first)
    assert_equal [ 1, 2 ], results.map(&:last).sort
    products = @owner.business.products.order(:id)
    assert_equal 2, products.pluck(:sku).uniq.size
    assert_equal [ 3, 3 ], products.pluck(:quantity)
    assert_equal 2, @owner.business.inventory_logs.count
    products.each { |product| assert_equal product.quantity, product.inventory_logs.sum(:quantity_delta) }
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end
