require "test_helper"

class BrevoDeliveryTest < ActionMailer::TestCase
  class FakeDelivery < BrevoDelivery
    attr_accessor :responses
    attr_reader :requests

    def initialize(settings)
      super
      @requests = []
    end

    private
      def send_request(request)
        @requests << request
        response = @responses.shift
        raise response if response.is_a?(Exception)
        response
      end

      def pause(_seconds)
      end
  end

  setup do
    @mail = PasswordsMailer.reset(create_owner).message
    @delivery = FakeDelivery.new(api_key: SecureRandom.hex(32), origin: ProductionSettings::ORIGIN)
    @requests = @delivery.requests
  end

  test "HTTPS API receives branded html and plain text with a public logo URL" do
    response = api_response(201, '{"messageId":"accepted-disposable-id"}')
    @delivery.responses = [ response ]
    assert_equal @mail, @delivery.deliver!(@mail)
    request = @requests.sole
    assert_equal "https", BrevoDelivery::ENDPOINT.scheme
    assert_equal "/v3/smtp/email", request.path
    payload = JSON.parse(request.body)
    assert_equal [ { "email" => @mail.to.sole } ], payload.fetch("to")
    assert_includes payload.fetch("htmlContent"), "https://lefty-wefty.devs.surf/brand/logos/email-logo.png"
    refute_includes payload.fetch("htmlContent"), "cid:"
    assert_equal @mail.text_part.body.decoded, payload.fetch("textContent")
    assert payload.fetch("htmlContent").include?("Reset your password")
    assert payload.fetch("headers").fetch("idempotencyKey").present?
  end

  test "throttles retry once with the same idempotency key and stop for long backoffs" do
    responses = [ api_response(429), api_response(201, '{"messageId":"accepted-id"}') ]
    @delivery.responses = responses
    @delivery.deliver!(@mail)
    assert_equal 2, @requests.size
    assert_equal @requests.first.body, @requests.last.body
    throttled = api_response(429)
    throttled["Retry-After"] = "60"
    @requests.clear
    @delivery.responses = [ throttled ]
    error = assert_raises(BrevoDelivery::Failed) { @delivery.deliver!(@mail) }
    assert_equal :rate_limited, error.reason
    assert_equal 1, @requests.size
  end

  test "rejections malformed responses and ambiguous timeouts are sanitized and never retried" do
    [ api_response(400, "private-provider-detail"), api_response(503), api_response(201, "invalid json"), api_response(201, "{}") ].each do |response|
      @requests.clear
      @delivery.responses = [ response ]
      error = assert_raises(BrevoDelivery::Failed) { @delivery.deliver!(@mail) }
      refute_includes error.message, "private-provider-detail"
      assert_equal 1, @requests.size
    end
    @requests.clear
    @delivery.responses = [ Net::ReadTimeout.new("private-reset-token") ]
    error = assert_raises(BrevoDelivery::Failed) { @delivery.deliver!(@mail) }
    refute_includes error.message, "private-reset-token"
    assert_equal :connection, error.reason
    assert_equal 1, @requests.size
  end

  private
    def api_response(code, body = "")
      response = Net::HTTPResponse.new("1.1", code.to_s, "Disposable API response")
      response.instance_variable_set(:@read, true)
      response.body = body
      response
    end
end
