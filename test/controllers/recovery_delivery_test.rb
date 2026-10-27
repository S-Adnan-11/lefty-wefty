require "test_helper"

class RecoveryDeliveryTest < ActionDispatch::IntegrationTest
  class RejectedDelivery
    def initialize(_settings)
    end

    def deliver!(_mail)
      raise BrevoDelivery::Failed, :rejected
    end
  end

  test "a rejected provider request keeps the same generic response for known and unknown accounts" do
    owner = create_owner
    previous_mode = Rails.application.config.x.password_recovery_delivery
    previous_delivery = ActionMailer::Base.delivery_method
    ActionMailer::Base.add_delivery_method :rejected_recovery, RejectedDelivery
    Rails.application.config.x.password_recovery_delivery = :email
    ActionMailer::Base.delivery_method = :rejected_recovery
    post passwords_path, params: { email_address: owner.email_address }
    assert_redirected_to new_session_path
    known_notice = flash[:notice]
    post passwords_path, params: { email_address: "unknown@example.test" }
    assert_redirected_to new_session_path
    assert_equal known_notice, flash[:notice]
    assert_equal "If an account matches that email, a reset email has been requested.", flash[:notice]
  ensure
    Rails.application.config.x.password_recovery_delivery = previous_mode
    ActionMailer::Base.delivery_method = previous_delivery
  end
end
