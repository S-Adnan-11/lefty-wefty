class SignupsController < ApplicationController
  allow_unauthenticated_access
  before_action :ensure_signup_available
  rate_limit to: 5, within: 3.minutes, only: :create, store: Rails.application.config.x.authentication_rate_limit_store,
    with: -> { redirect_to signup_path, alert: "Try again later." }

  def new
    @user = User.new
    @user.build_business
  end

  def create
    @user = User.new(params.expect(user: [ :email_address, :password, :password_confirmation ]))
    @user.build_business(params.expect(business: [ :name ]))
    if @user.save
      start_new_session_for @user
      redirect_to root_path, notice: "Your business workspace is ready."
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @user.errors.add(:email_address, "has already been taken")
    render :new, status: :unprocessable_entity
  end

  private
    def ensure_signup_available
      head :not_found unless Rails.application.config.x.public_signup
    end
end
