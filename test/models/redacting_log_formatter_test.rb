require "test_helper"

class RedactingLogFormatterTest < ActiveSupport::TestCase
  test "password reset credentials are redacted from request and redirect paths" do
    token = "sensitive-test-reset-credential"
    message = "Started GET /passwords/#{token}/edit and PUT /passwords/#{token}"
    rendered = RedactingLogFormatter.new.call("INFO", Time.current, nil, message)
    assert_not_includes rendered, token
    assert_includes rendered, "/passwords/[FILTERED]/edit"
    assert_equal "Ordinary log entry\n", RedactingLogFormatter.new.call("INFO", Time.current, nil, "Ordinary log entry")
  end
end
