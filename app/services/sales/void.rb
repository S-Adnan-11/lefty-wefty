module Sales
  class Void
    def self.call(business:, actor:, order_id:, reason:, acknowledged:)
      Draft.authorize!(business, actor)
      reason = reason.to_s.strip
      raise Rejected, "Confirm that you intend to void this recorded sale" unless acknowledged.to_s == "1"
      raise Rejected, "Supply a void reason of 1 to 500 characters" unless reason.length.between?(1, 500)
      Order.transaction(requires_new: true) do
        order = business.orders.lock.find(order_id)
        if order.voided?
          raise Rejected, "This sale was already voided with a different reason. Its original void record is unchanged." unless order.void_reason == reason
          next order
        end
        raise Rejected, "Only a confirmed sale can be voided" unless order.confirmed?
        items = order.order_items.order(:product_id).to_a
        products = business.products.where(id: items.map(&:product_id)).order(:id).lock.index_by(&:id)
        items.each do |item|
          Stock::Apply.sale!(business: business, actor: actor, product: products.fetch(item.product_id), item: item, reversal: true)
        end
        order.update!(state: "voided", voided_at: Time.current, voided_by: actor, void_reason: reason)
        order
      end
    end
  end
end
