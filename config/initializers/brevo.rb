require Rails.root.join("lib/brevo_delivery")

ActionMailer::Base.add_delivery_method :brevo, BrevoDelivery
if Rails.env.production? && ENV["LEFTY_WEFTY_BREVO_ENABLED"] == "true"
  Rails.application.config.x.password_recovery_delivery = :email
  ActionMailer::Base.delivery_method = :brevo
  ActionMailer::Base.brevo_settings = { api_key: ENV["BREVO_API_KEY"], origin: ProductionSettings::ORIGIN }
end
