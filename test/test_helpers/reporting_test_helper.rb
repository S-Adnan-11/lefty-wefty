module ReportingTestHelper
  def reporting_stock(business, sku:, price: 2500, quantity: 100)
    product = create_product(business, sku: sku, name: "Report #{sku}", price_minor: price)
    change_stock(product, quantity)
    product
  end

  def recorded_sale(business, at:, lines:)
    travel_to at do
      order = Sales::Draft.call(business: business, actor: business.owner, submission_key: SecureRandom.uuid,
        lines: lines.map { |product, quantity| { product_id: product.id, quantity: quantity } })
      Sales::Confirm.call(business: business, actor: business.owner, order_id: order.id,
        revision: order.revision, review_token: order.review_token)
    end
  end

  def void_sale(order, at: Time.utc(2025, 3, 12))
    travel_to at do
      Sales::Void.call(business: order.business, actor: order.business.owner, order_id: order.id,
        reason: "Fictional correction", acknowledged: "1")
    end
  end
end
