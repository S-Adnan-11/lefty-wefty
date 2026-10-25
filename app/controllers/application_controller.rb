class ApplicationController < ActionController::Base
  include Authentication
  before_action :prevent_private_page_caching
  around_action :use_business_timezone
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private
    def prevent_private_page_caching
      response.headers["Cache-Control"] = "no-store"
    end

    def use_business_timezone(&action)
      Time.use_zone(Current.business&.timezone || "UTC", &action)
    end
end
