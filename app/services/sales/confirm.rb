module Sales
  class Confirm
    def self.call(business:, actor:, order_id:, revision:, review_token:)
      Draft.authorize!(business, actor)
      revised = false
      order = Order.transaction(requires_new: true) do
        order = business.orders.lock.find(order_id)
        # Return the current recorded result even if the original review is old.
        next order unless order.draft?
        Draft.review!(order, revision, review_token.to_s)
        items = order.order_items.order(:product_id).to_a
        lines = items.map { |item| { product_id: item.product_id, quantity: item.quantity } }
        products = Draft.products!(business, lines)
        quote, total = Draft.quote(lines, products)
        if quote != order.quote
          order.update!(quote: quote, total_minor: total, review_token: SecureRandom.uuid, revision: order.revision + 1)
          revised = true
          next order
        end
        items.zip(quote).each do |item, line|
          item.update!(product_name: line.fetch("name"), product_sku: line.fetch("sku"),
            unit_price_minor: line.fetch("unit_price_minor"), line_total_minor: line.fetch("line_total_minor"))
          Stock::Apply.sale!(business: business, actor: actor, product: products.find { |p| p.id == item.product_id }, item: item)
        end
        order.update!(state: "confirmed", confirmed_at: Time.current, confirmed_by: actor)
        order
      end
      raise ReviewChanged, "Prices or product details changed. Review the revised total, then record the sale again." if revised
      order
    end
  end
end
