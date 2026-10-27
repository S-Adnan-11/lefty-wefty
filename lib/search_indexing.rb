class SearchIndexing
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    public_page = status == 200 && env["lefty_wefty.public_page"] && PublicSite.indexing?
    headers["x-robots-tag"] = public_page ? "index, follow" : "noindex, nofollow"
    [ status, headers, body ]
  end
end
