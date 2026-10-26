require "test_helper"
require "zlib"

class BusinessSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_owner
    @other = create_owner(email: "other@example.test")
    sign_in_as(@owner)
  end

  test "name logo replacement removal and initials survive new model instances" do
    patch business_settings_path, params: { business: { name: "Rice & More", logo: image_upload,
      owner_id: @other.id, id: @other.business.id, currency: "USD" } }
    assert_response :redirect, css_select(".errors").map(&:text).join
    assert_redirected_to edit_business_settings_path
    business = @owner.business.reload
    assert_equal "Rice & More", business.name
    assert_equal @owner.id, business.owner_id
    assert_equal "NGN", business.currency
    assert_equal "Cedar Supplies", @other.business.reload.name
    assert business.logo.attached?
    assert business.logo_display.attached?
    original = business.logo.blob
    display = business.logo_display.blob
    assert_equal "image/png", original.content_type
    assert_equal "image/png", display.content_type
    assert display.service.exist?(display.key)
    get logo_business_settings_path
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal display.download, response.body.b
    assert_match(/\A\x89PNG/n, response.body.b)
    patch business_settings_path, params: { business: { name: "Rice & More", logo: image_upload(format: "WEBP") } }
    assert_response :redirect
    assert_equal "image/webp", business.reload.logo.blob.content_type
    assert_not_equal original.id, business.logo.blob.id
    patch business_settings_path, params: { business: { name: "Rice & More", remove_logo: "1" } }
    assert_response :redirect
    assert_not business.reload.logo.attached?
    assert_not business.logo_display.attached?
    get logo_business_settings_path
    assert_response :not_found
    get edit_business_settings_path
    assert_select "#logo-preview span", "R&"
  end

  test "invalid name corrupt oversized mismatched and unsupported replacements retain current name and logo" do
    patch business_settings_path, params: { business: { name: "Original", logo: image_upload(format: "JPEG") } }
    assert_response :redirect
    business = @owner.business.reload
    keys = [ business.logo.blob.key, business.logo_display.blob.key ]
    logo_ids = [ business.logo.blob.id, business.logo_display.blob.id ]
    inputs = [ { name: "", logo: image_upload }, { name: "Changed", logo: upload("broken", "image/png") },
      { name: "Changed", logo: upload("x" * (2.megabytes + 1), "image/png") },
      { name: "Changed", logo: upload(png_bytes.byteslice(0, 35), "image/png") },
      { name: "Changed", logo: image_upload(type: "image/jpeg") },
      { name: "Changed", logo: upload("<svg></svg>", "image/svg+xml") },
      { name: "Changed", logo: image_upload(width: 4097) },
      { name: "Changed", logo: image_upload(width: 3000, height: 3000) },
      { name: "Changed", logo: image_upload, remove_logo: "1" } ]
    inputs.each do |attributes|
      assert_no_difference "ActiveStorage::Blob.count" do
        patch business_settings_path, params: { business: attributes }
        assert_response :unprocessable_entity
        assert_select ".business-name", "Original"
      end
      business.reload
      assert_equal "Original", business.name
      assert_equal logo_ids, [ business.logo.blob.id, business.logo_display.blob.id ]
      keys.each { |key| assert business.logo.blob.service.exist?(key) }
    end
  end

  test "foreign signed blob IDs and serving URLs do not authorize access or attachment" do
    foreign = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("private"), filename: "foreign.png", content_type: "image/png")
    @other.business.logo.attach(foreign)
    patch business_settings_path, params: { business: { name: "Changed", logo: foreign.signed_id, id: @other.business.id } }
    assert_response :unprocessable_entity
    assert_equal "Cedar Supplies", @owner.business.reload.name
    assert_not @owner.business.logo.attached?
    assert_equal foreign.id, @other.business.reload.logo.blob.id
    get "/rails/active_storage/blobs/redirect/#{foreign.signed_id}/foreign.png"
    assert_response :not_found
    post "/rails/active_storage/direct_uploads", params: { blob: { filename: "forged.png" } }
    assert_response :not_found
    delete session_path
    [ edit_business_settings_path, logo_business_settings_path, account_path ].each do |path|
      get path
      assert_redirected_to new_session_path
    end
    patch business_settings_path, params: { business: { name: "Forged" } }
    assert_redirected_to new_session_path
    patch account_path, params: { user: { password: "Forged" } }
    assert_redirected_to new_session_path
  end

  private
    def png_bytes(width: 2, height: 2)
      chunk = ->(name, data) { [ data.bytesize ].pack("N") + name + data + [ Zlib.crc32(name + data) ].pack("N") }
      "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNC5")) +
        chunk.call("IDAT", Zlib::Deflate.deflate(("\x00".b + "\x24\x5c\x43".b * width) * height)) + chunk.call("IEND", "".b)
    end

    def upload(bytes, type)
      Tempfile.create([ "logo-test", ".png" ], binmode: true) do |file|
        file.write(bytes)
        file.flush
        Rack::Test::UploadedFile.new(file.path, type, true)
      end
    end

    def image_upload(format: "PNG", type: nil, **dimensions)
      bytes = png_bytes(**dimensions)
      if format != "PNG"
        Tempfile.create([ "source", ".png" ], binmode: true) do |input|
          input.write(bytes)
          input.flush
          Tempfile.create([ "converted", ".#{format.downcase}" ], binmode: true) do |output|
            MiniMagick.convert { |command| command << "PNG:#{input.path}" << "#{format}:#{output.path}" }
            bytes = File.binread(output.path)
          end
        end
      end
      upload(bytes, type || Businesses::LogoImage::TYPES.fetch(format))
    end
end
