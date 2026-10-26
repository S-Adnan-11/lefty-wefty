class AccountsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :update,
    store: Rails.application.config.x.authentication_rate_limit_store,
    with: -> { redirect_to account_path, alert: "Too many attempts. Try again later." }

  def show
    @user = Current.user
  end

  def update
    @user = Current.user
    attributes = params.expect(user: [ :current_password, :password, :password_confirmation ])
    changed = @user.with_lock do
      unless @user.authenticate(attributes[:current_password].to_s)
        @user.errors.add(:current_password, "is incorrect")
        next false
      end
      if attributes[:password].blank? || attributes[:password_confirmation].blank?
        @user.errors.add(:password, "and confirmation are required")
        next false
      end
      if @user.update(attributes.except(:current_password))
        @user.sessions.destroy_all
        Current.session = nil
        start_new_session_for(@user)
        true
      else
        false
      end
    end
    if changed
      redirect_to account_path, notice: "Password changed. Your other sessions have been logged out.", status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  end
end
