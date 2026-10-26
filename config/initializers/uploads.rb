local_path = Rails.root.join("config/uploads.local.yml")
local = local_path.exist? ? YAML.safe_load_file(local_path) : {}
Rails.application.config.active_storage.service = Rails.env.test? ? :test : ENV.fetch("LEFTY_WEFTY_STORAGE_SERVICE", "local").to_sym
if Rails.env.production? && Rails.application.config.active_storage.service == :local && ENV["LEFTY_WEFTY_UPLOAD_ROOT"].blank? && local["root"].blank?
  raise "Configure persistent upload storage before starting production"
end
image_path = ENV.fetch("LEFTY_WEFTY_IMAGE_MAGICK_PATH", local["image_magick_path"])
ENV["PATH"] = [ image_path, ENV["PATH"] ].compact.join(File::PATH_SEPARATOR)
MiniMagick.configure do |config|
  config.timeout = 10
  config.logger = Logger.new(File::NULL)
  config.cli_env = {
    "PATH" => [ image_path, ENV["PATH"] ].compact.join(File::PATH_SEPARATOR),
    "MAGICK_CONFIGURE_PATH" => Rails.root.join("config/image_policy").to_s
  }
end
