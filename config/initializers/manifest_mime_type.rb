# Rails' static file server uses Rack's MIME registry.
Rack::Mime::MIME_TYPES[".webmanifest"] = "application/manifest+json"
