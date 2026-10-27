require "open3"
require "net/http"
require "json"
require "pg"
require "fileutils"
require "aws-sdk-s3"

abort "Disposable CI only." unless ENV["GITHUB_ACTIONS"] == "true" && ENV["LEFTY_WEFTY_CI_DIRECTORY"]
directory = ENV.fetch("LEFTY_WEFTY_CI_DIRECTORY")
network = ENV.fetch("LEFTY_WEFTY_CI_NETWORK")
production_env = File.join(directory, "production.env")
secrets = File.readlines(production_env).filter_map do |line|
  name, value = line.strip.split("=", 2)
  value if name.match?(/PASSWORD|SECRET|KEY|DATABASE_URL/) && value
end
secrets << ENV.fetch("LEFTY_WEFTY_DB_PASSWORD")

def command!(*arguments, secrets: [])
  output, error, status = Open3.capture3(*arguments)
  unless status.success?
    details = (output + error).byteslice(-6000, 6000) || output + error
    secrets.each { |secret| details = details.gsub(secret, "[FILTERED]") }
    warn details.gsub(%r{(/passwords/)[^/?\s"'<>]+}, '\1[FILTERED]')
    raise "Disposable production check failed."
  end
  output
end

def wait_for_web
  90.times do
    begin
      http = Net::HTTP.new("127.0.0.1", 53000)
      http.open_timeout = http.read_timeout = 2
      request = Net::HTTP::Get.new("/up")
      request["Host"] = "lefty-wefty.devs.surf"
      return if http.request(request).code == "200"
    rescue IOError, SystemCallError, Timeout::Error
      # A cold process may still be migrating or booting.
    end
    sleep 1
  end
  raise "Production process did not become healthy."
end

launch = [ "docker", "run", "--detach", "--name", "lefty-wefty-ci-web", "--network", network,
  "--publish", "127.0.0.1:53000:3000", "--env-file", production_env, "--volume", "#{directory}:/ci:ro", "lefty-wefty-ci" ]
probe = [ "docker", "exec", "lefty-wefty-ci-web", "env", "-u", "MIGRATION_DATABASE_URL", "bundle", "exec", "ruby", "bin/rails", "runner", "script/ci/production_probe.rb" ]
command!(*launch, secrets: secrets)
wait_for_web
command!(*probe, "create", secrets: secrets)
puts "Production startup and create/workflow probe passed."
command!("docker", "exec", "lefty-wefty-ci-web", "env", "LEFTY_WEFTY_BACKUP_CONFIRMED_MAINTENANCE=true",
  "bundle", "exec", "ruby", "bin/rails", "runner", "script/export_logos.rb", "/tmp/lefty-wefty-logo-export", secrets: secrets)
command!("docker", "cp", "lefty-wefty-ci-web:/tmp/lefty-wefty-logo-export", File.join(directory, "logo-export"))
command!("sudo", "chown", "-R", "1000:1000", File.join(directory, "logo-export"))
admin_options = JSON.parse(File.read(File.join(directory, "admin.json")), symbolize_names: true)
connection = PG.connect(**admin_options)
connection.exec("CREATE DATABASE lefty_wefty_restore_ci OWNER ci_migration")
source_values = File.readlines(production_env).to_h { |line| line.strip.split("=", 2) }
migration = URI(source_values.fetch("MIGRATION_DATABASE_URL"))
pg_env = {
  "PGHOST" => "127.0.0.1", "PGPORT" => "55433", "PGUSER" => migration.user, "PGPASSWORD" => migration.password,
  "PGDATABASE" => "lefty_wefty_ci_production", "PGSSLMODE" => "verify-full", "PGSSLROOTCERT" => File.join(directory, "certs/ca.crt"), "PGCHANNELBINDING" => "require"
}
dump = File.join(directory, "production.dump")
command!(pg_env, "pg_dump", "--format=custom", "--no-owner", "--no-acl", "--file", dump, secrets: secrets)
command!(pg_env.merge("PGDATABASE" => "lefty_wefty_restore_ci"), "pg_restore", "--no-owner", "--no-acl", "--exit-on-error", "--dbname", "lefty_wefty_restore_ci", dump, secrets: secrets)
restored = PG.connect(**admin_options.merge(dbname: "lefty_wefty_restore_ci"))
restored.exec("GRANT USAGE ON SCHEMA public TO ci_runtime")
restored.exec("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ci_runtime")
restored.exec("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ci_runtime")
restored.close
storage = Aws::S3::Client.new(endpoint: "https://localhost:59000", region: source_values.fetch("LEFTY_WEFTY_S3_REGION"),
  access_key_id: source_values.fetch("LEFTY_WEFTY_S3_ACCESS_KEY_ID"), secret_access_key: source_values.fetch("LEFTY_WEFTY_S3_SECRET_ACCESS_KEY"),
  force_path_style: true, ssl_ca_bundle: File.join(directory, "certs/ca.crt"), retry_limit: 0,
  request_checksum_calculation: "when_required", response_checksum_validation: "when_required")
key = storage.list_objects_v2(bucket: "lefty-wefty-ci-logos").contents.first.key
unsigned = Net::HTTP.new("localhost", 59000)
unsigned.use_ssl = true
unsigned.ca_file = File.join(directory, "certs/ca.crt")
raise "Logo objects allow unsigned access" unless unsigned.get("/lefty-wefty-ci-logos/#{key}").code == "403"
storage.create_bucket(bucket: "lefty-wefty-ci-restore")
restore_values = source_values.merge("DATABASE_URL" => source_values.fetch("DATABASE_URL").sub("/lefty_wefty_ci_production", "/lefty_wefty_restore_ci"),
  "LEFTY_WEFTY_S3_BUCKET" => "lefty-wefty-ci-restore", "LEFTY_WEFTY_RESTORE_EXPECTED_BUCKET" => "lefty-wefty-ci-restore", "LEFTY_WEFTY_RESTORE_CONFIRM" => "isolated-target")
restore_env = File.join(directory, "restore.env")
File.write(restore_env, restore_values.map { |name, value| "#{name}=#{value}" }.join("\n") + "\n", perm: 0o600)
restore_run = [ "docker", "run", "--rm", "--network", network, "--env-file", restore_env, "--volume", "#{directory}:/ci:ro", "--entrypoint", "bundle", "lefty-wefty-ci", "exec", "ruby", "bin/rails", "runner" ]
command!(*restore_run, "script/restore_logos.rb", "/ci/logo-export", secrets: secrets)
command!(*restore_run, "script/ci/production_probe.rb", "clone_verify", secrets: secrets)
connection.close
puts "Private object access and isolated database/object export and restore passed."
command!("docker", "pause", "lefty-wefty-ci-objects")
begin
  command!(*probe, "storage_failure", secrets: secrets)
ensure
  command!("docker", "unpause", "lefty-wefty-ci-objects")
end
puts "Storage outage preserves the existing profile."
command!("docker", "stop", "lefty-wefty-ci-web")
command!("docker", "rm", "lefty-wefty-ci-web")
command!(*launch, secrets: secrets)
wait_for_web
command!(*probe, "verify", secrets: secrets)
status = command!("docker", "exec", "lefty-wefty-ci-web", "cat", "/proc/1/status")
rss = status.match(/^VmRSS:\s+(\d+) kB$/)&.captures&.first.to_i
raise "Unexpected production memory footprint" unless rss.positive? && rss < 400 * 1024
environment = command!("docker", "exec", "lefty-wefty-ci-web", "cat", "/proc/1/environ")
raise "Web process inherited migration credentials" if environment.split("\0").any? { |entry| entry.start_with?("MIGRATION_DATABASE_URL=") }
puts "Fresh-container persistence and logo lifecycle passed; single web process RSS #{rss} KiB."
connection = PG.connect(**admin_options.merge(dbname: "lefty_wefty_ci_production"))
tables = %w[users businesses products inventory_logs orders order_items sale_submissions sessions active_storage_blobs active_storage_attachments]
fingerprint = -> do
  tables.to_h { |table| [ table, connection.exec("SELECT md5(COALESCE(string_agg(to_jsonb(t)::text, '' ORDER BY id), '')) FROM #{table} t").getvalue(0, 0) ] }
end
before = fingerprint.call
failure = File.join(directory, "20991231235959_failure_probe.rb")
File.write(failure, <<~RUBY)
  class FailureProbe < ActiveRecord::Migration[8.1]
    def change
      create_table(:ci_failure_marker) { |table| table.string :name }
      raise "Disposable migration failure"
    end
  end
RUBY
output, error, failure_status = Open3.capture3("docker", "run", "--name", "lefty-wefty-ci-failed-start", "--network", network,
  "--env-file", production_env, "--volume", "#{directory}:/ci:ro", "--volume", "#{failure}:/rails/db/migrate/20991231235959_failure_probe.rb:ro", "lefty-wefty-ci")
File.write(File.join(directory, "expected-migration-failure.txt"), output + error, perm: 0o600)
raise "Expected migration to prevent startup" if failure_status.success?
raise "Failed migration left a partial table" unless connection.exec("SELECT to_regclass('public.ci_failure_marker')").getvalue(0, 0).nil?
raise "Failed migration altered application rows" unless fingerprint.call == before
running = command!("docker", "inspect", "--format", "{{.State.Running}}", "lefty-wefty-ci-failed-start").strip
raise "An incompatible web process started" unless running == "false"
connection.close
puts "Migration failure prevents web startup, rolls back DDL and preserves earlier data."
