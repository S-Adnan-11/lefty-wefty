module ApplicationHelper
  def money_minor(amount)
    "₦#{number_with_delimiter(amount / 100)}.#{format('%02d', amount % 100)}"
  end

  def sale_status(state)
    { "draft" => "Draft", "confirmed" => "Completed", "voided" => "Cancelled" }.fetch(state)
  end

  def movement_label(kind)
    { "opening" => "Starting stock", "receipt" => "Stock received", "adjustment" => "Correction", "sale" => "Sale", "sale_void" => "Sale cancelled" }.fetch(kind)
  end

  def movement_reason(movement)
    { "Opening stock" => "Starting stock", "Recorded sale voided" => "Sale cancelled" }.fetch(movement.reason, movement.reason)
  end

  def business_initials(business)
    business.name.to_s.split.filter_map { |word| word[0] }.first(2).join.upcase.presence || "B"
  end

  def business_avatar(business)
    if business.logo_display.attached?
      image_tag logo_business_settings_path, alt: "#{business.name} logo", width: 48, height: 48
    else
      tag.span(business_initials(business), aria: { label: "#{business.name} initials" })
    end
  end

  def navigation_link(label, path, active:)
    link_to label, path, class: active ? "nav-link active" : "nav-link", aria: { current: active ? "page" : nil }
  end

  def signed_units(quantity)
    quantity.positive? ? "+#{number_with_delimiter(quantity)}" : number_with_delimiter(quantity)
  end

  def local_time(time)
    time.in_time_zone(Current.business.timezone).strftime("%d %b %Y, %H:%M")
  end

  def stock_badge(product)
    text, style = if product.archived?
      [ "Archived", "neutral" ]
    elsif product.low_stock?
      [ "Low stock", "warning" ]
    else
      [ "In stock", "positive" ]
    end
    tag.span(text, class: "badge #{style}")
  end
end
