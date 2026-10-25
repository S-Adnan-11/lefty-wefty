module ApplicationHelper
  def money_minor(amount)
    "#{Current.business.currency} #{number_with_delimiter(amount / 100)}.#{format('%02d', amount % 100)}"
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
