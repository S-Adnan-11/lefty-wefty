class PasswordsMailer < ApplicationMailer
  def reset(user)
    unless %i[local email].include?(Rails.application.config.x.password_recovery_delivery)
      raise "Password recovery delivery is not configured"
    end
    @user = user
    @reset_url = edit_password_url(@user.password_reset_token)
    mail subject: "Reset your password", to: user.email_address
  end
end
