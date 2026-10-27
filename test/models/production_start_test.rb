require "test_helper"
require_relative "../../lib/production_start"

class ProductionStartTest < ActiveSupport::TestCase
  class Connection
    attr_reader :closed, :unlocked
    def exec_params(query, _parameters)
      @unlocked = true if query.include?("unlock")
    end

    def close
      @closed = true
    end
  end

  class FailedStart < ProductionStart
    attr_accessor :connection
    attr_reader :started

    private
      def connect(_url)
        @connection
      end

      def acquire_lock(_connection)
      end

      def migrate(_url)
        false
      end

      def start_web(_url)
        @started = true
      end
  end

  test "migration failure never starts the web process and releases its lock" do
    start = FailedStart.new(settings)
    connection = Connection.new
    start.connection = connection
    assert_raises(ProductionSettings::Invalid) { start.run }
    refute start.started
    assert connection.closed
    assert connection.unlocked
  end

  test "migration and web credentials can differ but must identify the same database" do
    env = settings
    env["MIGRATION_DATABASE_URL"] = env.fetch("MIGRATION_DATABASE_URL").sub("/app", "/other")
    assert_raises(ProductionSettings::Invalid) { ProductionStart.new(env).run }
  end

  private
    def settings
      {
        "RAILS_ENV" => "production", "SECRET_KEY_BASE" => SecureRandom.hex(64),
        "DATABASE_URL" => "postgresql://runtime:disposable@database.example/app?sslmode=verify-full",
        "MIGRATION_DATABASE_URL" => "postgresql://migration:disposable@database.example/app?sslmode=verify-full",
        "LEFTY_WEFTY_STORAGE_SERVICE" => "s3", "LEFTY_WEFTY_S3_ENDPOINT" => "https://objects.example",
        "LEFTY_WEFTY_S3_REGION" => "us-east-2", "LEFTY_WEFTY_S3_BUCKET" => "private-logos",
        "LEFTY_WEFTY_S3_ACCESS_KEY_ID" => "disposable", "LEFTY_WEFTY_S3_SECRET_ACCESS_KEY" => SecureRandom.hex(32)
      }
    end
end
