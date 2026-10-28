require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)
require_relative "../lib/redacting_log_formatter"
require_relative "../lib/search_indexing"
require_relative "../lib/production_settings"

module LeftyWefty
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1
    config.active_record.schema_format = :sql
    config.active_job.queue_adapter = :async
    config.log_formatter = RedactingLogFormatter.new
    config.x.password_recovery_delivery = :unavailable
    config.x.public_signup = true
    config.x.mail_sender = ENV["LEFTY_WEFTY_MAIL_FROM"]
    config.x.public_origin = ENV["LEFTY_WEFTY_PUBLIC_ORIGIN"]
    config.x.public_indexing = ENV["LEFTY_WEFTY_PUBLIC_INDEXING"] == "true"
    config.middleware.insert_before 0, SearchIndexing
    # All logo reads go through the authenticated business controller.
    config.active_storage.draw_routes = false
    config.active_storage.analyzers = []
    config.active_storage.previewers = []
    config.active_storage.variant_processor = :disabled

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
