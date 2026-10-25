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
    assert_select "[role=status]", /external email delivery is not configured/i
  end

  test "unknown account gives the same response without mail" do
    assert_no_emails { post passwords_path, params: { email_address: "missing@example.test" } }
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=status]", /reset instructions have been prepared/i
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
end
