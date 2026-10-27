require "pg"
require "timeout"
require_relative "production_settings"

class ProductionStart
  LOCK_KEY = 8_675_309_001

  def initialize(env = ENV)
    @env = env
  end

  def run
    raise ProductionSettings::Invalid, "Use RAILS_ENV=production." unless @env["RAILS_ENV"] == "production"
    ProductionSettings.validate!(@env)
    runtime_url = ProductionSettings.database_url(@env["DATABASE_URL"], @env)
    migration_url = ProductionSettings.database_url(@env["MIGRATION_DATABASE_URL"], @env)
    runtime, migration = URI(runtime_url), URI(migration_url)
    unless runtime.path == migration.path && runtime.host.sub(/-pooler(?=\.)/, "") == migration.host && (runtime.port || 5432) == (migration.port || 5432)
      raise ProductionSettings::Invalid, "Migration and runtime URLs must identify the same database, using its direct migration endpoint."
    end
    connection = connect(migration_url)
    begin
      acquire_lock(connection)
      unless migrate(migration_url)
        raise ProductionSettings::Invalid, "Migrations failed; the web process was not started."
      end
    ensure
      connection.exec_params("SELECT pg_advisory_unlock($1)", [ LOCK_KEY ])
      connection.close
    end
    start_web(runtime_url)
  rescue PG::Error
    raise ProductionSettings::Invalid, "Production PostgreSQL could not be verified; the web process was not started."
  end

  private
    def connect(url)
      PG.connect(url)
    end

    def acquire_lock(connection)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
      loop do
        return if connection.exec_params("SELECT pg_try_advisory_lock($1)", [ LOCK_KEY ]).getvalue(0, 0) == "t"
        raise ProductionSettings::Invalid, "Migration lock is busy; retry startup later." if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 1
      end
    end

    def migrate(url)
      pid = Process.spawn({ "DATABASE_URL" => url, "MIGRATION_DATABASE_URL" => nil, "PGOPTIONS" => "-c lock_timeout=10000 -c statement_timeout=120000" },
        "bundle", "exec", "ruby", "bin/rails", "db:migrate")
      Timeout.timeout(180) { Process.wait(pid) }
      $?.success?
    rescue Timeout::Error
      Process.kill("TERM", pid)
      begin
        Timeout.timeout(5) { Process.wait(pid) }
      rescue Timeout::Error
        Process.kill("KILL", pid)
        Process.wait(pid)
      end
      false
    end

    def start_web(url)
      exec({ "DATABASE_URL" => url, "MIGRATION_DATABASE_URL" => nil }, "bundle", "exec", "puma", "-C", "config/puma.rb")
    end
end
