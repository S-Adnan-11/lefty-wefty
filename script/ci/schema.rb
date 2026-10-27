require "pg"
require "open3"
require "json"

abort "Disposable CI only." unless ENV["GITHUB_ACTIONS"] == "true" && ENV["LEFTY_WEFTY_CI_DIRECTORY"]
directory = ENV.fetch("LEFTY_WEFTY_CI_DIRECTORY")
base = {
  host: ENV.fetch("LEFTY_WEFTY_DB_HOST"), port: ENV.fetch("LEFTY_WEFTY_DB_PORT"), user: ENV.fetch("LEFTY_WEFTY_DB_USER"),
  password: ENV.fetch("LEFTY_WEFTY_DB_PASSWORD"), sslmode: "verify-full", sslrootcert: ENV.fetch("PGSSLROOTCERT"), channel_binding: "require"
}
contracts = []
def command!(env, *command, input: "")
  output, error, status = Open3.capture3(env, *command, stdin_data: input)
  unless status.success?
    File.write(File.join(ENV.fetch("LEFTY_WEFTY_CI_DIRECTORY"), "schema-error.txt"), output + error, perm: 0o600)
    details = (output + error).byteslice(-4000, 4000) || output + error
    details = details.gsub(ENV.fetch("LEFTY_WEFTY_DB_PASSWORD"), "[FILTERED]")
    warn details.gsub(%r{postgres(?:ql)?://[^\s"'<>]+}, "[FILTERED_DATABASE_URL]")
    raise "Isolated schema check failed; no application data was used."
  end
end
%w[fresh restore upgrade].each do |kind|
  database = "lefty_wefty_ci_#{kind}"
  connection = PG.connect(**base.merge(dbname: database))
  raise "Expected empty CI schema" unless connection.exec("SELECT count(*) FROM information_schema.tables WHERE table_schema='public'").getvalue(0, 0) == "0"
  url = "postgresql://#{base.fetch(:user)}:#{base.fetch(:password)}@#{base.fetch(:host)}:#{base.fetch(:port)}/#{database}?sslmode=verify-full"
  env = { "RAILS_ENV" => "development", "DATABASE_URL" => url }
  before = nil
  case kind
  when "restore"
    command!({ "PGDATABASE" => database, "PGHOST" => base.fetch(:host), "PGPORT" => base.fetch(:port), "PGUSER" => base.fetch(:user), "PGPASSWORD" => base.fetch(:password) },
      "psql", "-X", "-v", "ON_ERROR_STOP=1", "-f", "db/structure.sql")
  when "fresh"
    command!(env, "bundle", "exec", "ruby", "bin/rails", "db:migrate")
  when "upgrade"
    command!(env, "bundle", "exec", "ruby", "bin/rails", "db:migrate", "VERSION=20261025150001")
    code = <<~RUBY
      raise "Unsafe upgrade target" unless ActiveRecord::Base.connection_db_config.database == "lefty_wefty_ci_upgrade"
      owner = User.create!(email_address: "upgrade@example.test", password: SecureRandom.hex(24))
      business = Business.create!(owner: owner, name: "Existing Upgrade Business")
      product = business.products.create!(name: "Existing Product", sku: "UPGRADE", price_minor: 125050, low_stock_threshold: 2)
      Stock::Apply.call(business: business, actor: owner, product_id: product.id, change: StockChange.new(kind: "receipt", quantity: 7, operation_key: SecureRandom.uuid))
    RUBY
    command!(env, "bundle", "exec", "ruby", "bin/rails", "runner", "-", input: code)
    before = %w[users businesses products inventory_logs].to_h do |table|
      [ table, connection.exec("SELECT md5(string_agg(to_jsonb(t)::text, '' ORDER BY id)) FROM #{table} t").getvalue(0, 0) ]
    end
    command!(env, "bundle", "exec", "ruby", "bin/rails", "db:migrate")
    after = before.keys.to_h do |table|
      [ table, connection.exec("SELECT md5(string_agg(to_jsonb(t)::text, '' ORDER BY id)) FROM #{table} t").getvalue(0, 0) ]
    end
    raise "Upgrade altered existing records" unless before == after
  end
  contract = {
    constraints: connection.exec("SELECT conrelid::regclass::text, conname, pg_get_constraintdef(oid) FROM pg_constraint WHERE connamespace='public'::regnamespace ORDER BY 1,2").values,
    triggers: connection.exec("SELECT tgrelid::regclass::text, tgname, pg_get_triggerdef(oid) FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN (SELECT oid FROM pg_class WHERE relnamespace='public'::regnamespace) ORDER BY 1,2").values,
    functions: connection.exec("SELECT proname, pg_get_functiondef(oid) FROM pg_proc WHERE pronamespace='public'::regnamespace ORDER BY proname").values
  }
  raise "Expected transaction/tenant constraints and triggers" unless contract[:constraints].size >= 20 && contract[:triggers].size >= 5
  contracts << contract
  unless kind == "upgrade"
    raise "Schema setup unexpectedly seeded users" unless connection.exec("SELECT count(*) FROM users").getvalue(0, 0) == "0"
  end
  connection.close
  puts "Isolated PostgreSQL #{kind} schema verified."
end
raise "Migrations, SQL restore and upgrade disagree" unless contracts.uniq.size == 1
command!({ "RAILS_ENV" => "test" }, "bundle", "exec", "ruby", "bin/rails", "db:migrate")
puts "Schema contracts agree; dedicated regression database is ready."
