class SearchIndexing
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers = headers.dup
    path = env["PATH_INFO"].to_s
    public_asset = (path.start_with?("/assets/", "/brand/") || path == "/favicon.ico") && env["action_dispatch.request.path_parameters"].to_h.empty?
    public_page = status == 200 && env["lefty_wefty.public_page"] && PublicSite.indexing_for?(Rack::Request.new(env))
    headers["x-robots-tag"] = public_page ? "index, follow" : "noindex, nofollow" unless public_asset && status < 400
    [ status, headers, body ]
  end
end
