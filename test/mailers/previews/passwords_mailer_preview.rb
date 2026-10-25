# Preview all emails at http://localhost:3000/rails/mailers/passwords_mailer
class PasswordsMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/passwords_mailer/reset
  def reset
    user = params[:email].present? ? User.find_by!(email_address: params[:email]) : User.first!
    PasswordsMailer.reset(user)
  end
end
