require "test_helper"

class PublicSiteTest < ActionDispatch::IntegrationTest
  setup do
    @origin = Rails.application.config.x.public_origin
    @indexing = Rails.application.config.x.public_indexing
    Rails.application.config.x.public_origin = nil
    Rails.application.config.x.public_indexing = false
  end

  teardown do
    Rails.application.config.x.public_origin = @origin
    Rails.application.config.x.public_indexing = @indexing
  end

  test "anonymous introduction works without indexing or absolute metadata" do
    get root_path, params: { token: "untrusted-query" }
    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "h1", text: "Stock and sales, in order.", count: 1
    assert_select "title", PublicSite::TITLE
    assert_select "meta[name=description]", count: 1
    assert_select "meta[name=robots][content='noindex, nofollow']", count: 1
    assert_select "link[rel=canonical], meta[property='og:url'], meta[property='og:image'], script[type='application/ld+json']", count: 0
    assert_select "a[href=?]", signup_path, text: "Create account"
    assert_select "a[href=?]", new_session_path, text: "Log in"
    assert_select ".business-name, #month-sales-value", count: 0
    get "/sitemap.xml"
    assert_response :not_found
    get "/robots.txt"
    assert_response :success
    assert_equal "User-agent: *\nAllow: /\n", response.body
  end

  test "configured public metadata ignores host and query input and sitemap allows only the public root" do
    enable_indexing
    get root_path, params: { token: "secret-query", business_id: "999" }, headers: { "HTTP_HOST" => "untrusted.example" }
    assert_response :success
    assert_equal "index, follow", response.headers["X-Robots-Tag"]
    assert_select "link[rel=canonical][href='https://stock.example/']", count: 1
    assert_select "meta[property='og:url'][content='https://stock.example/']", count: 1
    assert_select "meta[property='og:image'][content='https://stock.example/brand/social/og-image.png']", count: 1
    assert_select "meta[property='og:image:width'][content='1200']"
    assert_select "meta[property='og:image:height'][content='630']"
    assert_select "meta[name='twitter:card'][content='summary_large_image']", count: 1
    structured = css_select("script[type='application/ld+json']")
    assert_equal 1, structured.size
    website = JSON.parse(structured.first.text)
    assert_equal "WebSite", website.fetch("@type")
    assert_equal "Lefty-Wefty", website.fetch("name")
    assert_equal "https://stock.example/", website.fetch("url")
    refute response.body.include?("secret-query")
    refute response.body.include?("https://untrusted.example")
    get "/sitemap.xml", headers: { "HTTP_HOST" => "untrusted.example" }
    assert_response :success
    assert_equal [ "https://stock.example/" ], Nokogiri::XML(response.body).remove_namespaces!.css("loc").map(&:text)
    refute response.body.include?("lastmod")
    get "/robots.txt"
    assert_includes response.body, "Sitemap: https://stock.example/sitemap.xml"
    refute response.body.include?("Disallow")
  end

  test "invalid origins and a disabled indexing switch fail closed" do
    [ "http://stock.example", "https://user:pass@stock.example", "https://stock.example/path", "https://stock.example?token=x", "https://stock.example/#x", "https://localhost", "https://127.0.0.1", "https://stock.example:8443", "garbage" ].each do |origin|
      Rails.application.config.x.public_origin = origin
      Rails.application.config.x.public_indexing = true
      assert_nil PublicSite.origin, origin
      get root_path
      assert_select "link[rel=canonical]", count: 0
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    end
    enable_indexing
    Rails.application.config.x.public_indexing = false
    get root_path
    assert_select "link[rel=canonical], meta[property='og:image']", count: 0
    get "/sitemap.xml"
    assert_response :not_found
  end

  test "browser identity assets have the expected formats and manifest paths" do
    get "/brand/site.webmanifest"
    assert_response :success
    assert_equal "application/manifest+json", response.media_type
    manifest = JSON.parse(response.body)
    assert_equal "browser", manifest.fetch("display")
    assert_equal "Lefty-Wefty", manifest.fetch("name")
    assert_equal 2, manifest.fetch("icons").count { |icon| icon["purpose"] == "maskable" }
    manifest.fetch("icons").each do |icon|
      get icon.fetch("src")
      assert_response :success
      assert_equal "image/png", response.media_type
      width, height = response.body.b[16, 8].unpack("NN")
      assert_equal icon.fetch("sizes"), "#{width}x#{height}"
    end
  end

  test "auth tokens private pages attachments and errors stay out of indexing" do
    enable_indexing
    [ new_session_path, signup_path, new_password_path, edit_password_path("not-a-token"), products_path, orders_path, report_path, stock_movements_path, account_path, logo_business_settings_path ].each do |path|
      get path
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"], path
      assert_select "link[rel=canonical], meta[property='og:url'], script[type='application/ld+json']", count: 0
    end
    owner = create_owner(name: "Private business name")
    product = create_product(owner.business)
    sign_in_as(owner)
    [ root_path, products_path, product_path(product), orders_path, stock_movements_path, report_path, account_path, edit_business_settings_path ].each do |path|
      get path
      assert_response :success
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
      assert_select "meta[name=robots][content='noindex, nofollow']"
      assert_select "link[rel=canonical], meta[property='og:url'], script[type='application/ld+json']", count: 0
      assert_select "meta[property='og:title'][content*='Private business']", count: 0
    end
    get "/not-a-real-page"
    assert_response :not_found
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    get "/rails/active_storage/blobs/redirect/not-a-token/logo.png"
    assert_response :not_found
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  test "names retain spaces case punctuation and unicode through signup settings and display" do
    name = "Test Business — Ọlá & Co. <Shop>"
    post signup_path, params: { user: { email_address: "display@example.test", password: "a safe test passphrase", password_confirmation: "a safe test passphrase" }, business: { name: "  #{name}  " } }
    owner = User.find_by!(email_address: "display@example.test")
    assert_equal name, owner.business.name
    follow_redirect!
    assert_select "h1", "Overview"
    assert_select ".business-name", name
    assert_select "shop", count: 0
    get edit_business_settings_path
    assert_select "input[name='business[name]'][value=?]", name
    updated = "Àṣà  Market's & Sons"
    patch business_settings_path, params: { business: { name: updated } }
    assert_equal updated, owner.business.reload.name
    get root_path
    assert_equal updated, css_select(".business-name").sole.text
    get edit_business_settings_path
    assert_select "input[name='business[name]'][value=?]", updated
  end

  private
    def enable_indexing
      Rails.application.config.x.public_origin = "https://stock.example/"
      Rails.application.config.x.public_indexing = true
    end
end
