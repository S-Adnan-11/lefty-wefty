class BusinessSettingsController < ApplicationController
  def edit
    @business = Current.business
  end

  def update
    # Keep the saved header identity separate from invalid form values.
    @business = Business.find(Current.business.id)
    attributes = params.expect(business: [ :name, :logo, :remove_logo ])
    if Businesses::UpdateProfile.call(business: @business, actor: Current.user, name: attributes[:name],
        upload: attributes[:logo], remove_logo: attributes[:remove_logo] == "1")
      redirect_to edit_business_settings_path, notice: "Business settings saved.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def logo
    attachment = Current.business.logo_display
    raise ActiveRecord::RecordNotFound unless attachment.attached?
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_data attachment.download, type: "image/png", disposition: "inline", filename: "business-logo.png"
  end
end
