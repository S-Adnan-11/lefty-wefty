require "uri"

module ProductionSettings
  class Invalid < StandardError; end
  ORIGIN = "https://lefty-wefty.devs.surf"
  HOST = "lefty-wefty.devs.surf"

  def self.assets_build?
    ENV["SECRET_KEY_BASE_DUMMY"] == "1" && defined?(Rake) &&
      Rake.application.top_level_tasks == [ "assets:precompile" ]
  end

  def self.database_url(value, env = ENV)
    uri = URI.parse(value.to_s)
    unless %w[postgres postgresql].include?(uri.scheme) && uri.host && !uri.user.to_s.empty? && !uri.password.to_s.empty? && uri.path.to_s.length > 1 && !uri.fragment
      raise Invalid, "Configure a complete production DATABASE_URL."
    end
    query = URI.decode_www_form(uri.query.to_s).to_h
    if query["sslmode"] && query["sslmode"] != "verify-full"
      raise Invalid, "Production PostgreSQL requires sslmode=verify-full."
    end
    query.merge!("sslmode" => "verify-full", "sslrootcert" => env.fetch("LEFTY_WEFTY_DB_SSLROOTCERT", "system"), "connect_timeout" => "5", "channel_binding" => "require", "gssencmode" => "disable")
    uri.query = URI.encode_www_form(query)
    uri.to_s
  rescue URI::InvalidURIError, ArgumentError
    raise Invalid, "Configure a valid production DATABASE_URL."
  end

  def self.https_endpoint!(value)
    uri = URI.parse(value.to_s)
    unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.query && !uri.fragment
      raise Invalid, "Configure an HTTPS object-storage endpoint."
    end
    value
  rescue URI::InvalidURIError
    raise Invalid, "Configure a valid HTTPS object-storage endpoint."
  end

  def self.validate!(env = ENV)
    raise Invalid, "Dummy secrets are only supported for asset compilation." if env["SECRET_KEY_BASE_DUMMY"]
    raise Invalid, "Configure a production SECRET_KEY_BASE of at least 64 characters." if env["SECRET_KEY_BASE"].to_s.length < 64
    database_url(env["DATABASE_URL"], env)
    raise Invalid, "Production logos require the private s3 storage service." unless env["LEFTY_WEFTY_STORAGE_SERVICE"] == "s3"
    %w[LEFTY_WEFTY_S3_ENDPOINT LEFTY_WEFTY_S3_REGION LEFTY_WEFTY_S3_BUCKET LEFTY_WEFTY_S3_ACCESS_KEY_ID LEFTY_WEFTY_S3_SECRET_ACCESS_KEY].each do |key|
      raise Invalid, "Configure #{key} for private object storage." if env[key].to_s.empty?
    end
    https_endpoint!(env["LEFTY_WEFTY_S3_ENDPOINT"])
    if env["LEFTY_WEFTY_PUBLIC_ORIGIN"] && env["LEFTY_WEFTY_PUBLIC_ORIGIN"] != ORIGIN
      raise Invalid, "The production public origin must match the configured domain."
    end
    preview = env["LEFTY_WEFTY_PREVIEW_HOST"]
    if preview && !preview.empty? && !preview.match?(/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.onrender\.com\z/)
      raise Invalid, "Configure only the assigned Render preview hostname."
    end
    raise Invalid, "Use a single production web process." unless env.fetch("WEB_CONCURRENCY", "1") == "1"
    raise Invalid, "Use one or two production request threads." unless %w[1 2].include?(env.fetch("RAILS_MAX_THREADS", "2"))
    if env["LEFTY_WEFTY_BREVO_ENABLED"] == "true"
      raise Invalid, "Configure the Brevo API key before enabling recovery." if env["BREVO_API_KEY"].to_s.empty?
      sender = env["LEFTY_WEFTY_MAIL_FROM"].to_s
      unless sender.match?(/\A[^\s<>@]+@(?:mail\.)?lefty-wefty\.devs\.surf\z/)
        raise Invalid, "Configure a verified sender address under the production domain."
      end
    end
    true
  end
end
