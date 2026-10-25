require "test_helper"

class AccountsTest < ActionDispatch::IntegrationTest
  test "signup creates one owner and server-owned business together" do
    foreign = create_owner(email: "other@example.test")
    assert_difference [ "User.count", "Business.count", "Session.count" ], 1 do
      post signup_path, params: {
        user: { email_address: " NEW@EXAMPLE.TEST ", password: "new owner passphrase", password_confirmation: "new owner passphrase", business_id: foreign.business.id },
        business: { name: "New business", owner_id: foreign.id, currency: "USD", timezone: "UTC" }
      }
    end
    user = User.find_by!(email_address: "new@example.test")
    assert_equal user.id, user.business.owner_id
    assert_equal "NGN", user.business.currency
    assert_equal "Africa/Lagos", user.business.timezone
    follow_redirect!
    assert_response :success
    assert_select "h1", "New business"
  end

  test "invalid business or user leaves no partial signup" do
    [ { name: "", email: "new@example.test" }, { name: "Valid business", email: "invalid" } ].each do |input|
      assert_no_difference [ "User.count", "Business.count", "Session.count" ] do
        post signup_path, params: { user: { email_address: input[:email], password: "valid test passphrase", password_confirmation: "valid test passphrase" }, business: { name: input[:name] } }
      end
      assert_response :unprocessable_entity
      assert_select "[role=alert]"
    end
  end

  test "expired sessions and logged-out cookies cannot access the workspace" do
    user = create_owner
    sign_in_as(user)
    session_id = Current.session.id
    get root_path
    assert_response :success
    Session.find(session_id).update!(created_at: 15.days.ago)
    get root_path
    assert_redirected_to new_session_path
    post session_path, params: { email_address: user.email_address, password: "test owner passphrase" }
    delete session_path
    get root_path
    assert_redirected_to new_session_path
  end

  test "signup and login are throttled with a real cache" do
    6.times { post signup_path, params: { user: { email_address: "bad", password: "bad" }, business: { name: "" } } }
    assert_redirected_to signup_path
    follow_redirect!
    assert_select "[role=alert]", /Try again later/
    11.times { post session_path, params: { email_address: "missing@example.test", password: "bad" } }
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=alert]", /Try again later/
  end
end
