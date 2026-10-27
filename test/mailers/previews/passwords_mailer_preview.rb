# Preview all emails at http://localhost:3000/rails/mailers/passwords_mailer
class PasswordsMailerPreview < ActionMailer::Preview
  PreviewAccount = Data.define(:email_address, :password_reset_token, :password_reset_token_expires_in)
  # Preview this email at http://localhost:3000/rails/mailers/passwords_mailer/reset
  def reset
    # The template preview never looks up an account or creates usable credentials.
    account = PreviewAccount.new(email_address: "preview@example.test", password_reset_token: "preview-only",
      password_reset_token_expires_in: User.new.password_reset_token_expires_in)
    PasswordsMailer.reset(account)
  end
end
