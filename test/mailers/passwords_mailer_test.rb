require "test_helper"
require_relative "previews/passwords_mailer_preview"

class PasswordsMailerTest < ActionMailer::TestCase
  test "html and text mail use the same requested-account link and actual expiry" do
    user = create_owner
    message = PasswordsMailer.reset(user).message
    assert_equal [ "no-reply@example.test" ], message.from
    assert_equal [ user.email_address ], message.to
    assert_equal "Reset your password", message.subject
    html = Nokogiri::HTML(message.html_part.body.decoded)
    assert_equal "Lefty-Wefty", html.at_css("title").text
    assert_equal "Reset password", html.at_css("a").text
    assert html.at_css("a")["style"].include?("#1d4ed8")
    url = html.at_css("a")["href"]
    assert message.text_part.body.decoded.include?(url)
    assert_equal user.id, User.find_by_password_reset_token(URI(url).path.split("/")[2]).id
    assert html.text.include?("15 minutes")
    assert html.text.include?("you can ignore this email")
    assert message.text_part.body.decoded.include?("you can ignore this email")
  end

  test "preview is fictional even when an existing email is supplied" do
    user = create_owner
    queries = []
    callback = ->(event) { queries << event.payload[:sql] if event.payload[:sql].match?(/FROM "users"/i) }
    message = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      PasswordsMailerPreview.new(email: user.email_address).reset.message
    end
    assert_empty queries
    assert_equal [ "preview@example.test" ], message.to
    url = Nokogiri::HTML(message.html_part.body.decoded).at_css("a")["href"]
    assert_nil User.find_by_password_reset_token(URI(url).path.split("/")[2])
    assert_equal "preview-only", URI(url).path.split("/")[2]
  end
end
