require "test_helper"

class ProductionSettingsTest < ActiveSupport::TestCase
  def settings
    {
      "SECRET_KEY_BASE" => SecureRandom.hex(64),
      "DATABASE_URL" => "postgresql://service:disposable@database.example/app?sslmode=verify-full",
      "LEFTY_WEFTY_STORAGE_SERVICE" => "s3",
      "LEFTY_WEFTY_S3_ENDPOINT" => "https://objects.example",
      "LEFTY_WEFTY_S3_REGION" => "us-east-2",
      "LEFTY_WEFTY_S3_BUCKET" => "private-logos",
      "LEFTY_WEFTY_S3_ACCESS_KEY_ID" => "disposable-access",
      "LEFTY_WEFTY_S3_SECRET_ACCESS_KEY" => SecureRandom.hex(32)
    }
  end

  test "production fails closed for missing secrets database or private persistent storage" do
    valid = settings
    assert ProductionSettings.validate!(valid)
    valid.keys.each do |key|
      assert_raises(ProductionSettings::Invalid, key) { ProductionSettings.validate!(valid.except(key)) }
    end
    [ "local", "test" ].each do |storage|
      assert_raises(ProductionSettings::Invalid) { ProductionSettings.validate!(valid.merge("LEFTY_WEFTY_STORAGE_SERVICE" => storage)) }
    end
    assert_raises(ProductionSettings::Invalid) { ProductionSettings.validate!(valid.merge("SECRET_KEY_BASE_DUMMY" => "1")) }
    assert_raises(ProductionSettings::Invalid) { ProductionSettings.validate!(valid.merge("WEB_CONCURRENCY" => "2")) }
    assert_raises(ProductionSettings::Invalid) { ProductionSettings.validate!(valid.merge("RAILS_MAX_THREADS" => "8")) }
  end

  test "database connections enforce certificate hostname and channel verification without exposing a secret" do
    value = settings.fetch("DATABASE_URL")
    uri = URI(ProductionSettings.database_url(value, {}))
    query = URI.decode_www_form(uri.query).to_h
    assert_equal "verify-full", query.fetch("sslmode")
    assert_equal "system", query.fetch("sslrootcert")
    assert_equal "require", query.fetch("channel_binding")
    [ nil, "sqlite:///tmp/app", "postgresql://host/app", value.sub("verify-full", "require"), value.sub("verify-full", "disable") ].each do |url|
      error = assert_raises(ProductionSettings::Invalid) { ProductionSettings.database_url(url) }
      refute_includes error.message, "disposable"
    end
    custom = URI(ProductionSettings.database_url(value, "LEFTY_WEFTY_DB_SSLROOTCERT" => "/secure/ca.pem"))
    assert_equal "/secure/ca.pem", URI.decode_www_form(custom.query).to_h.fetch("sslrootcert")
  end

  test "storage endpoints and production preview hosts are restricted" do
    valid = settings
    [ "http://objects.example", "https://user:secret@objects.example", "https://objects.example?secret=x" ].each do |endpoint|
      assert_raises(ProductionSettings::Invalid) { ProductionSettings.validate!(valid.merge("LEFTY_WEFTY_S3_ENDPOINT" => endpoint)) }
    end
    assert ProductionSettings.validate!(valid.merge("LEFTY_WEFTY_PREVIEW_HOST" => "assigned-service.onrender.com"))
    assert_raises(ProductionSettings::Invalid) { ProductionSettings.validate!(valid.merge("LEFTY_WEFTY_PREVIEW_HOST" => "untrusted.example")) }
    assert_raises(ProductionSettings::Invalid) { ProductionSettings.validate!(valid.merge("LEFTY_WEFTY_PUBLIC_ORIGIN" => "https://untrusted.example")) }
  end

  test "recovery remains optional and enabling it requires credentials and a domain sender" do
    valid = settings.merge("LEFTY_WEFTY_BREVO_ENABLED" => "true")
    assert_raises(ProductionSettings::Invalid) { ProductionSettings.validate!(valid) }
    valid["BREVO_API_KEY"] = SecureRandom.hex(32)
    assert_raises(ProductionSettings::Invalid) { ProductionSettings.validate!(valid) }
    valid["LEFTY_WEFTY_MAIL_FROM"] = "recovery@lefty-wefty.devs.surf"
    assert ProductionSettings.validate!(valid)
    assert_raises(ProductionSettings::Invalid) { ProductionSettings.validate!(valid.merge("LEFTY_WEFTY_MAIL_FROM" => "personal@example.test")) }
  end
end
