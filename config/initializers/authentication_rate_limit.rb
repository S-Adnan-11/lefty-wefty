# One local Puma process shares this bounded store across authentication routes.
Rails.application.config.x.authentication_rate_limit_store = ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)
