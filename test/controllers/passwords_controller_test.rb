require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = create_owner }

  test "recovery pages and local reset delivery" do
    get new_password_path
    assert_response :success
    assert_emails 1 do
      post passwords_path, params: { email_address: @user.email_address }
    end
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=status]", /If an account matches that email, a reset link has been prepared/
  end

  test "unknown account gives the same response without mail" do
    assert_no_emails { post passwords_path, params: { email_address: "missing@example.test" } }
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=status]", /If an account matches that email, a reset link has been prepared/
  end

  test "reset validates password and revokes every previous session and reset token" do
    old_session = @user.sessions.create!
    token = @user.password_reset_token
    get edit_password_path(token)
    assert_response :success
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "short", password_confirmation: "different" }
      assert_response :unprocessable_entity
    end
    put password_path(token), params: { password: "replacement test passphrase", password_confirmation: "replacement test passphrase" }
    assert_redirected_to new_session_path
    assert @user.reload.authenticate("replacement test passphrase")
    assert_not Session.exists?(old_session.id)
    get edit_password_path(token)
    assert_redirected_to new_password_path
  end

  test "invalid and expired reset tokens are rejected" do
    get edit_password_path("invalid")
    assert_redirected_to new_password_path
    token = @user.password_reset_token
    travel 16.minutes do
      get edit_password_path(token)
      assert_redirected_to new_password_path
    end
  end

  test "captured mail matches requested normalized account and opening it changes nothing" do
    other = create_owner(email: "other@example.test")
    session = @user.sessions.create!
    before = @user.password_digest
    post passwords_path, params: { email_address: " #{@user.email_address.upcase} " }
    notice = flash[:notice]
    message = ActionMailer::Base.deliveries.last
    assert_equal [ @user.email_address ], message.to
    text = message.text_part.body.decoded
    url = URI.extract(text).find { |value| value.start_with?("http") }
    token = URI(url).path.split("/")[2]
    assert_equal @user.id, User.find_by_password_reset_token(token).id
    assert text.include?("15 minutes")
    assert message.html_part.body.decoded.include?(url)
    get URI(url).request_uri
    assert_response :success
    assert_equal before, @user.reload.password_digest
    assert Session.exists?(session.id)
    assert_not other.authenticate("replacement test passphrase")
    post passwords_path, params: { email_address: "missing@example.test" }
    assert_equal notice, flash[:notice]
    follow_redirect!
    assert_not response.body.include?(token), "Acknowledgement must not contain credentials"
  end

  test "blank or omitted passwords and confirmations never succeed or revoke sessions" do
    session = @user.sessions.create!
    token = @user.password_reset_token
    before = @user.password_digest
    [ {}, { password: "", password_confirmation: "" }, { password: "replacement test passphrase" },
      { password: "replacement test passphrase", password_confirmation: "" },
      { password: "replacement test passphrase", password_confirmation: "different test passphrase" } ].each do |attributes|
      put password_path(token), params: attributes
      assert_response :unprocessable_entity
      assert_equal before, @user.reload.password_digest
      assert Session.exists?(session.id)
      assert_select "input[type=password][value]", count: 0
      assert_select "input[aria-invalid=true]"
    end
  end

  test "real captured reset logs in with the new password and rejects reuse" do
    session = @user.sessions.create!
    post passwords_path, params: { email_address: @user.email_address }
    url = URI.extract(ActionMailer::Base.deliveries.last.text_part.body.decoded).find { |value| value.start_with?("http") }
    token = URI(url).path.split("/")[2]
    put password_path(token), params: { password: "replacement test passphrase", password_confirmation: "replacement test passphrase" }
    assert_redirected_to new_session_path
    assert_not Session.exists?(session.id)
    assert_nil User.find_by_password_reset_token(token)
    put password_path(token), params: { password: "another test passphrase", password_confirmation: "another test passphrase" }
    assert_redirected_to new_password_path
    post session_path, params: { email_address: @user.email_address, password: "replacement test passphrase" }
    assert_redirected_to root_url
  end

  test "unconfigured delivery exposes no working form and sends no mail" do
    original = Rails.application.config.x.password_recovery_delivery
    Rails.application.config.x.password_recovery_delivery = :unavailable
    get new_password_path
    assert_response :success
    assert_select "form[action=?]", passwords_path, count: 0
    assert_select "p", /Password recovery is not available/
    assert_no_emails { post passwords_path, params: { email_address: @user.email_address } }
    assert_redirected_to new_password_path
    get edit_password_path(@user.password_reset_token)
    assert_redirected_to new_password_path
    assert_raises(RuntimeError) { PasswordsMailer.reset(@user).message }
  ensure
    Rails.application.config.x.password_recovery_delivery = original
  end
end
