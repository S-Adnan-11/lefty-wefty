class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.application.config.x.mail_sender }
  layout "mailer"
end
