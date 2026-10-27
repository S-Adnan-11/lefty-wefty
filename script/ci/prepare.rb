require "openssl"
require "securerandom"
require "fileutils"
require "json"
require "pg"
require "aws-sdk-s3"

abort "This script is limited to disposable GitHub-hosted CI." unless ENV["GITHUB_ACTIONS"] == "true" && ENV["RUNNER_TEMP"]
directory = File.join(ENV.fetch("RUNNER_TEMP"), "lefty-wefty-ci")
raise "CI directory already exists" if File.exist?(directory)
FileUtils.mkdir_p(File.join(directory, "certs"))
ca_key = OpenSSL::PKey::RSA.new(2048)
key = OpenSSL::PKey::RSA.new(2048)
ca = OpenSSL::X509::Certificate.new
ca.version, ca.serial = 2, 1
ca.subject = ca.issuer = OpenSSL::X509::Name.parse("/CN=Disposable CI CA")
ca.public_key, ca.not_before, ca.not_after = ca_key.public_key, Time.now - 60, Time.now + 86_400
factory = OpenSSL::X509::ExtensionFactory.new
factory.subject_certificate = factory.issuer_certificate = ca
ca.add_extension(factory.create_extension("basicConstraints", "CA:TRUE", true))
ca.add_extension(factory.create_extension("keyUsage", "keyCertSign,cRLSign", true))
ca.sign(ca_key, OpenSSL::Digest::SHA256.new)
certificate = OpenSSL::X509::Certificate.new
certificate.version, certificate.serial = 2, 2
certificate.subject, certificate.issuer = OpenSSL::X509::Name.parse("/CN=localhost"), ca.subject
certificate.public_key, certificate.not_before, certificate.not_after = key.public_key, Time.now - 60, Time.now + 86_400
factory.subject_certificate, factory.issuer_certificate = certificate, ca
certificate.add_extension(factory.create_extension("basicConstraints", "CA:FALSE", true))
certificate.add_extension(factory.create_extension("keyUsage", "digitalSignature,keyEncipherment", true))
certificate.add_extension(factory.create_extension("extendedKeyUsage", "serverAuth"))
certificate.add_extension(factory.create_extension("subjectAltName", "DNS:localhost,DNS:postgres,DNS:s3.test,IP:127.0.0.1"))
certificate.sign(ca_key, OpenSSL::Digest::SHA256.new)
{ "ca.crt" => ca.to_pem, "server.crt" => certificate.to_pem, "server.key" => key.to_pem,
  "public.crt" => certificate.to_pem, "private.key" => key.to_pem }.each do |name, contents|
  File.write(File.join(directory, "certs", name), contents, mode: "w", perm: 0o644)
end
database_password, migration_password, runtime_password = Array.new(3) { SecureRandom.hex(32) }
access_key, storage_secret = SecureRandom.hex(8), SecureRandom.hex(32)
File.write(File.join(directory, "postgres.env"), "POSTGRES_PASSWORD=#{database_password}\n", perm: 0o600)
File.write(File.join(directory, "minio.env"), "MINIO_ROOT_USER=#{access_key}\nMINIO_ROOT_PASSWORD=#{storage_secret}\n", perm: 0o600)
network = "lefty-wefty-ci-#{ENV.fetch('GITHUB_RUN_ID')}"
def command!(*arguments)
  raise "Disposable CI command failed: #{arguments.first}" unless system(*arguments)
end
command!("docker", "network", "create", network)
command!("docker", "run", "--detach", "--name", "lefty-wefty-ci-postgres", "--network", network, "--network-alias", "postgres",
  "--publish", "127.0.0.1:55433:5432", "--env-file", File.join(directory, "postgres.env"),
  "--volume", "#{directory}/certs:/certs:ro", "--entrypoint", "sh", "postgres:18.6",
  "-c", "cp /certs/server.key /tmp/server.key && chown postgres:postgres /tmp/server.key && chmod 600 /tmp/server.key && exec docker-entrypoint.sh postgres -c ssl=on -c ssl_cert_file=/certs/server.crt -c ssl_key_file=/tmp/server.key")
command!("docker", "run", "--detach", "--name", "lefty-wefty-ci-objects", "--network", network, "--network-alias", "s3.test", "--network-alias", "wrong.test",
  "--publish", "127.0.0.1:59000:9000", "--env-file", File.join(directory, "minio.env"),
  "--volume", "#{directory}/certs:/certs:ro", "quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z", "server", "/data", "--certs-dir", "/certs")
ca_path = File.join(directory, "certs/ca.crt")
admin_options = { host: "127.0.0.1", port: 55433, user: "postgres", password: database_password, dbname: "postgres", sslmode: "verify-full", sslrootcert: ca_path, channel_binding: "require", connect_timeout: 2 }
admin = nil
60.times do
  begin
    admin = PG.connect(**admin_options)
    break
  rescue PG::Error
    sleep 1
  end
end
raise "Disposable TLS PostgreSQL did not start" unless admin
{ "lefty_wefty" => database_password, "ci_migration" => migration_password, "ci_runtime" => runtime_password }.each do |role, password|
  admin.exec("CREATE ROLE #{admin.quote_ident(role)} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD #{admin.escape_literal(password)}")
end
%w[development test ci_fresh ci_restore ci_upgrade].each do |suffix|
  admin.exec("CREATE DATABASE #{admin.quote_ident('lefty_wefty_' + suffix)} OWNER lefty_wefty")
end
admin.exec("CREATE DATABASE lefty_wefty_ci_production OWNER ci_migration")
production = PG.connect(**admin_options.merge(dbname: "lefty_wefty_ci_production", user: "ci_migration", password: migration_password))
production.exec("GRANT USAGE ON SCHEMA public TO ci_runtime")
production.exec("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ci_runtime")
production.exec("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ci_runtime")
production.close
begin
  PG.connect(**admin_options.merge(host: "untrusted.example", hostaddr: "127.0.0.1"))
  raise "PostgreSQL accepted a mismatched TLS hostname"
rescue PG::ConnectionBad
  puts "PostgreSQL TLS hostname rejection verified."
end
storage = Aws::S3::Client.new(endpoint: "https://localhost:59000", region: "us-east-1", access_key_id: access_key,
  secret_access_key: storage_secret, force_path_style: true, ssl_ca_bundle: ca_path, retry_limit: 0,
  request_checksum_calculation: "when_required", response_checksum_validation: "when_required", http_open_timeout: 2, http_read_timeout: 3)
ready = false
60.times do
  begin
    storage.list_buckets
    ready = true
    break
  rescue Seahorse::Client::NetworkingError
    sleep 1
  end
end
raise "Disposable TLS object storage did not start" unless ready
storage.create_bucket(bucket: "lefty-wefty-ci-logos")
host_env = {
  "LEFTY_WEFTY_DB_HOST" => "127.0.0.1", "LEFTY_WEFTY_DB_PORT" => "55433", "LEFTY_WEFTY_DB_USER" => "lefty_wefty", "LEFTY_WEFTY_DB_PASSWORD" => database_password,
  "PGSSLMODE" => "verify-full", "PGSSLROOTCERT" => ca_path, "PGCHANNELBINDING" => "require", "LEFTY_WEFTY_CI_DIRECTORY" => directory,
  "LEFTY_WEFTY_CI_NETWORK" => network
}
File.open(ENV.fetch("GITHUB_ENV"), "a") { |file| host_env.each { |name, value| file.puts "#{name}=#{value}" } }
container_env = {
  "RAILS_ENV" => "production", "SECRET_KEY_BASE" => SecureRandom.hex(64), "RAILS_MAX_THREADS" => "2", "WEB_CONCURRENCY" => "1",
  "DATABASE_URL" => "postgresql://ci_runtime:#{runtime_password}@postgres/lefty_wefty_ci_production?sslmode=verify-full",
  "MIGRATION_DATABASE_URL" => "postgresql://ci_migration:#{migration_password}@postgres/lefty_wefty_ci_production?sslmode=verify-full",
  "LEFTY_WEFTY_DB_SSLROOTCERT" => "/ci/certs/ca.crt", "LEFTY_WEFTY_STORAGE_SERVICE" => "s3",
  "LEFTY_WEFTY_S3_ENDPOINT" => "https://s3.test:9000", "LEFTY_WEFTY_S3_REGION" => "us-east-1", "LEFTY_WEFTY_S3_BUCKET" => "lefty-wefty-ci-logos",
  "LEFTY_WEFTY_S3_ACCESS_KEY_ID" => access_key, "LEFTY_WEFTY_S3_SECRET_ACCESS_KEY" => storage_secret, "LEFTY_WEFTY_S3_CA_BUNDLE" => "/ci/certs/ca.crt",
  "LEFTY_WEFTY_PUBLIC_INDEXING" => "false", "LEFTY_WEFTY_PREVIEW_HOST" => "disposable-preview.onrender.com", "GITHUB_ACTIONS" => "true",
  "LEFTY_WEFTY_CI_PROBE" => "true", "LEFTY_WEFTY_SMOKE_PASSWORD" => SecureRandom.hex(24)
}
File.write(File.join(directory, "production.env"), container_env.map { |name, value| "#{name}=#{value}" }.join("\n") + "\n", perm: 0o600)
regression_env = host_env.merge("RAILS_ENV" => "test", "CI" => "true", "LEFTY_WEFTY_DB_HOST" => "postgres", "LEFTY_WEFTY_DB_PORT" => "5432", "PGSSLROOTCERT" => "/ci/certs/ca.crt")
File.write(File.join(directory, "regression.env"), regression_env.map { |name, value| "#{name}=#{value}" }.join("\n") + "\n", perm: 0o600)
File.write(File.join(directory, "admin.json"), JSON.generate(admin_options), perm: 0o600)
admin.close
puts "Disposable TLS database, roles and private S3-compatible storage prepared."
