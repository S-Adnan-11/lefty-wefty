require "action_dispatch/testing/integration"
require "rack/test"
require "digest"
require "open3"

targets = { "lefty_wefty_ci_production" => "lefty-wefty-ci-logos", "lefty_wefty_restore_ci" => "lefty-wefty-ci-restore" }
unless Rails.env.production? && ENV["GITHUB_ACTIONS"] == "true" && ENV["LEFTY_WEFTY_CI_PROBE"] == "true" &&
    targets[ActiveRecord::Base.connection_db_config.database] == ENV["LEFTY_WEFTY_S3_BUCKET"] && URI(ENV.fetch("LEFTY_WEFTY_S3_ENDPOINT")).host == "s3.test"
  abort "This write probe is limited to the disposable CI database and object store."
end
raise "Expected private S3 service" unless ActiveStorage::Blob.service.is_a?(ActiveStorage::Service::S3Service)
raise "Jobs must run synchronously" unless ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::InlineAdapter)
raise "Recovery must remain unavailable" unless Rails.application.config.x.password_recovery_delivery == :unavailable
raise "Mail delivery must remain disabled" if ActionMailer::Base.perform_deliveries
raise "Public signup must remain disabled" if Rails.application.config.x.public_signup
image_version, image_status = Open3.capture2("magick", "-version")
raise "Unexpected native image-processing version" unless image_status.success? && image_version.include?("ImageMagick 7.1.2-34 Q8")
raise "Unexpected production Ruby or Rails version" unless RUBY_VERSION == "3.4.12" && Rails.version == "8.1.4"
raise "System CA trust requires libpq 17 or newer" unless PG.library_version >= 170000

def session
  ActionDispatch::Integration::Session.new(Rails.application).tap do |client|
    client.host! ProductionSettings::HOST
    client.https!
  end
end

def document(client)
  Nokogiri::HTML(client.response.body)
end

def submit(client, verb, path, params)
  token = document(client).at_css('meta[name="csrf-token"]')&.[]("content")
  raise "Expected production CSRF token" unless token
  client.public_send(verb, path, params: params.merge(authenticity_token: token))
end

def success!(client, expected = 200)
  raise "Unexpected production response status" unless client.response.status == expected
end

def sign_in(client, email: "smoke-owner@example.test")
  client.get "/session/new"
  submit(client, :post, "/session", { email_address: email, password: ENV.fetch("LEFTY_WEFTY_SMOKE_PASSWORD") })
  raise "Expected login redirect" unless client.response.redirect?
  raise "Session cookie must be secure" unless Array(client.response.headers["set-cookie"]).join.downcase.include?("secure")
  # A prior protected request may return to a route this fixture cannot access.
  client.get "/"
  success!(client)
  raise "Expected authenticated overview" unless document(client).at_css("h1")&.text == "Overview"
end

def create_fixture_owner(email, name)
  User.transaction do
    owner = User.create!(email_address: email, password: ENV.fetch("LEFTY_WEFTY_SMOKE_PASSWORD"))
    Business.create!(owner: owner, name: name)
    owner
  end
end

client = session
client.get "/"
success!(client)
raise "Public indexing unexpectedly enabled" unless client.response.headers["X-Robots-Tag"] == "noindex, nofollow"
raise "Unexpected canonical while disabled" if document(client).at_css('link[rel="canonical"]')
raise "Production root is missing brand" unless document(client).at_css('.brand img[src="/brand/logos/logo-horizontal.svg"]')
client.get "/rails/mailers/passwords_mailer/reset"
success!(client, 404)
client.get "/passwords/new"
success!(client)
raise "Unconfigured recovery form exposed" if document(client).at_css('form[action="/passwords"]')
raise "Recovery message differs" unless document(client).text.include?("Password reset is currently unavailable.")
raise "Public signup link exposed" if document(client).at_css('a[href="/signup"]')
submit(client, :post, "/passwords", { email_address: "unknown@example.test" })
raise "Disabled recovery request accepted" unless client.response.redirect? && URI(client.response.location).path == "/passwords/new"
client.follow_redirect!
signup_counts = [ User.count, Business.count, Session.count ]
submit(client, :post, "/signup", { user: { email_address: "blocked@example.test", password: "blocked test passphrase", password_confirmation: "blocked test passphrase" }, business: { name: "Blocked signup" } })
success!(client, 404)
raise "Closed signup created records" unless signup_counts == [ User.count, Business.count, Session.count ]
client.get "/signup"
success!(client, 404)
client.get "/session/new"
client.post "/session", params: { email_address: "blocked@example.test" }
success!(client, 422)
foreign_host = session
foreign_host.host! "untrusted.example"
foreign_host.get "/"
success!(foreign_host, 403)
raise "Host rejections must be noindex" unless foreign_host.response.headers["X-Robots-Tag"] == "noindex, nofollow"
preview = session
preview.host! "disposable-preview.onrender.com"
preview.get "/"
success!(preview)
raise "Preview hostname must be noindex" unless preview.response.headers["X-Robots-Tag"] == "noindex, nofollow"
begin
  Rails.application.config.x.public_indexing = true
  preview.get "/"
  raise "Preview hostname became indexable" unless preview.response.headers["X-Robots-Tag"] == "noindex, nofollow" && !document(preview).at_css('link[rel="canonical"]')
  canonical = session
  canonical.get "/"
  raise "Canonical production URL differs from the intended origin" unless document(canonical).at_css('link[rel="canonical"]')&.[]("href") == "#{ProductionSettings::ORIGIN}/"
ensure
  Rails.application.config.x.public_indexing = false
end

if ARGV.first == "create"
  invalid_tls = Aws::S3::Client.new(endpoint: "https://wrong.test:9000", region: ENV.fetch("LEFTY_WEFTY_S3_REGION"),
    access_key_id: ENV.fetch("LEFTY_WEFTY_S3_ACCESS_KEY_ID"), secret_access_key: ENV.fetch("LEFTY_WEFTY_S3_SECRET_ACCESS_KEY"),
    force_path_style: true, ssl_ca_bundle: ENV.fetch("LEFTY_WEFTY_S3_CA_BUNDLE"), retry_limit: 0, http_open_timeout: 3, http_read_timeout: 3)
  begin
    invalid_tls.head_bucket(bucket: ENV.fetch("LEFTY_WEFTY_S3_BUCKET"))
    raise "Object storage accepted a mismatched TLS hostname"
  rescue Seahorse::Client::NetworkingError => error
    raise "Expected object-storage TLS rejection" unless error.original_error.is_a?(OpenSSL::SSL::SSLError)
  end
  owner = create_fixture_owner("smoke-owner@example.test", "Test Business — Ọlá & Co.")
  old_session = owner.sessions.create!
  original_digest = owner.password_digest
  reset_token = owner.password_reset_token
  client.get "/passwords/new"
  submit(client, :post, "/passwords", { email_address: owner.email_address })
  client.follow_redirect!
  client.get "/passwords/#{reset_token}/edit"
  raise "Stale reset page exposed" unless client.response.redirect? && URI(client.response.location).path == "/passwords/new"
  client.follow_redirect!
  %i[put patch].each do |verb|
    submit(client, verb, "/passwords/#{reset_token}", { password: "unwanted replacement passphrase", password_confirmation: "unwanted replacement passphrase" })
    raise "Disabled password reset accepted" unless client.response.redirect? && URI(client.response.location).path == "/passwords/new"
    client.follow_redirect!
  end
  raise "Disabled recovery mutated credentials or sessions" unless owner.reload.password_digest == original_digest && Session.exists?(old_session.id)
  sign_in(client)
  raise "Overview heading missing" unless document(client).at_css("h1").text == "Overview"
  client.get "/products/new"
  submit(client, :post, "/products", { product: { name: "CI Product", price_naira: "1,250.50", low_stock_threshold: 2 }, opening_quantity: "5" })
  raise "Product creation failed" unless client.response.redirect?
  product_path = URI(client.response.location).path
  client.follow_redirect!
  operation = document(client).at_css('input[name="stock_change[operation_key]"]')["value"]
  submit(client, :post, "#{product_path}/stock_movements", { stock_change: { kind: "receipt", quantity: "2", operation_key: operation } })
  client.follow_redirect!
  raise "Receipt failed" unless document(client).at_css("#quantity").text == "7"
  client.get "/orders/new"
  submission = document(client).at_css('input[name="order[submission_key]"]')["value"]
  product = User.find_by!(email_address: "smoke-owner@example.test").business.products.sole
  raise "Price lost precision" unless product.price_minor == 125050
  submit(client, :post, "/orders", { order: { submission_key: submission, lines: [ { product_id: product.id, quantity: 3 } ] } })
  raise "Draft failed" unless client.response.redirect?
  order_path = URI(client.response.location).path
  client.follow_redirect!
  raise "Draft total changed" unless document(client).at_css("#sale-total").text == "₦3,751.50"
  revision = document(client).at_css('input[name="revision"]')["value"]
  review = document(client).at_css('input[name="review_token"]')["value"]
  submit(client, :post, "#{order_path}/confirm", { revision: revision, review_token: review })
  client.follow_redirect!
  raise "Sale did not reduce stock" unless product.reload.quantity == 4
  submit(client, :post, "#{order_path}/void", { void_reason: "Disposable CI cancellation", acknowledged: "1" })
  client.follow_redirect!
  raise "Cancellation/history failed" unless product.reload.quantity == 7 && product.inventory_logs.count == 4
  client.get "/business_settings/edit"
  upload = Rack::Test::UploadedFile.new(Rails.root.join("public/brand/logos/mark.png"), "image/png", true)
  submit(client, :patch, "/business_settings", { business: { name: "Test Business — Ọlá & Co.", logo: upload } })
  raise "Logo upload failed" unless client.response.redirect?
  client.follow_redirect!
  client.get "/business_settings/logo"
  success!(client)
  raise "Logo was not sanitized" unless client.response.media_type == "image/png"
  blobs = product.business.reload
  raise "Both logo objects must persist" unless blobs.logo.attached? && blobs.logo_display.attached?
  [ blobs.logo.blob, blobs.logo_display.blob ].each do |blob|
    raise "Stored logo unavailable" unless blob.service.exist?(blob.key)
  end
  anonymous = session
  anonymous.get "/business_settings/logo"
  success!(anonymous, 302)
  create_fixture_owner("other-smoke@example.test", "Other CI Business")
  sign_in(anonymous, email: "other-smoke@example.test")
  anonymous.get "/business_settings/logo", params: { business_id: blobs.id }
  success!(anonymous, 404)
  anonymous.get "/products/#{product.id}"
  success!(anonymous, 404)
  anonymous.get "/rails/active_storage/blobs/redirect/#{blobs.logo.blob.signed_id}/logo.png"
  success!(anonymous, 404)
  puts "Production closed signup, disabled recovery, HTTPS/CSRF/session, tenant workflow and private logo upload verified."
elsif ARGV.first == "clone_verify"
  raise "Expected separate restore target" unless ActiveRecord::Base.connection_db_config.database == "lefty_wefty_restore_ci"
  sign_in(client)
  client.get "/business_settings/logo"
  success!(client)
  owner = User.find_by!(email_address: "smoke-owner@example.test")
  raise "Restored application data differs" unless owner.business.products.sole.quantity == 7 && owner.business.logo.attached?
  puts "Separate database/bucket restore serves the saved owner logo and stock."
elsif ARGV.first == "storage_failure"
  sign_in(client)
  business = User.find_by!(email_address: "smoke-owner@example.test").business
  original_name = business.name
  original_keys = [ business.logo.blob.key, business.logo_display.blob.key ]
  client.get "/business_settings/edit"
  upload = Rack::Test::UploadedFile.new(Rails.root.join("public/brand/logos/mark.png"), "image/png", true)
  submit(client, :patch, "/business_settings", { business: { name: "Must not persist", logo: upload } })
  success!(client, 422)
  business.reload
  raise "Storage failure changed saved profile" unless business.name == original_name && [ business.logo.blob.key, business.logo_display.blob.key ] == original_keys
  puts "Object-storage failure retains the saved business name and logo."
elsif ARGV.first == "verify"
  sign_in(client)
  client.get "/business_settings/logo"
  success!(client)
  business = User.find_by!(email_address: "smoke-owner@example.test").business
  product = business.products.sole
  raise "Data did not survive a fresh web container" unless product.quantity == 7 && product.price_minor == 125050 && business.logo_display.attached?
  raise "Downloaded logo differs from persistent object" unless Digest::SHA256.hexdigest(client.response.body.b) == Digest::SHA256.hexdigest(business.logo_display.download)
  service = business.logo.blob.service
  old_keys = [ business.logo.blob.key, business.logo_display.blob.key ]
  client.get "/business_settings/edit"
  upload = Rack::Test::UploadedFile.new(Rails.root.join("public/brand/icons/apple-touch-icon.png"), "image/png", true)
  submit(client, :patch, "/business_settings", { business: { name: business.name, logo: upload } })
  raise "Replacement failed" unless client.response.redirect?
  client.follow_redirect!
  raise "Old objects were not synchronously purged" if old_keys.any? { |key| service.exist?(key) }
  client.get "/business_settings/edit"
  submit(client, :patch, "/business_settings", { business: { name: business.name, remove_logo: "1" } })
  client.follow_redirect!
  client.get "/business_settings/logo"
  success!(client, 404)
  raise "Removal retained attachment metadata" if business.reload.logo.attached? || business.logo_display.attached?
  raise "Removal retained blob metadata" unless ActiveStorage::Blob.count.zero?
  puts "Fresh-container logo persistence, replace/remove and synchronous purges verified."
else
  abort "Choose create, storage_failure or verify."
end
