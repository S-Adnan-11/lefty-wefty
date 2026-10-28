class PasswordsController < ApplicationController
  helper_method :password_recovery_mode
  allow_unauthenticated_access
  before_action :ensure_recovery_available, only: %i[create edit update]
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, store: Rails.application.config.x.authentication_rate_limit_store,
    with: -> { redirect_to new_password_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.find_by(email_address: params.permit(:email_address)[:email_address].to_s)
      begin
        PasswordsMailer.reset(user).deliver_now
      rescue BrevoDelivery::Failed => error
        Rails.logger.warn("Password recovery delivery failed (#{error.reason}).")
      end
    end

    notice = password_recovery_mode == :local ?
      "If an account matches that email, a reset link has been prepared." :
      "If an account matches that email, a reset email has been requested."
    redirect_to new_session_path, notice: notice
  end

  def edit
  end

  def update
    attributes = params.permit(:password, :password_confirmation)
    result = @user.with_lock do
      # Recheck after locking: another successful reset invalidates this token.
      next :expired unless User.uncached { User.find_by_password_reset_token(params[:token]) }&.id == @user.id
      @user.errors.add(:password, "can't be blank") if attributes[:password].blank?
      @user.errors.add(:password_confirmation, "can't be blank") if attributes[:password_confirmation].blank?
      next false if @user.errors.any?
      if @user.update(attributes)
        @user.sessions.destroy_all
        true
      else
        false
      end
    end
    if result == :expired
      invalid_link
    elsif result
      cookies.delete(:session_id)
      Current.session = nil
      reset_session
      redirect_to new_session_path, notice: "Password reset. Log in with your new password."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def password_recovery_mode
      Rails.application.config.x.password_recovery_delivery
    end

    def ensure_recovery_available
      unless %i[local email].include?(password_recovery_mode)
        redirect_to new_password_path, alert: "Password reset is currently unavailable."
      end
    end

    def invalid_link
      redirect_to new_password_path, alert: "This reset link is invalid or has expired. Request a new link below."
    end

    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      invalid_link
    end
end
